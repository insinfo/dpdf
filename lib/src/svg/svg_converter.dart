import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_page.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/svg/processors/impl/default_svg_processor.dart';
import 'package:dpdf/src/svg/renderers/impl/pdf_root_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_css_utils.dart';

/// Converte SVG em conteúdo PDF.
///
/// Cobre a parte vetorial mais comum do formato: `svg`, `g`, `a`, `path`,
/// `rect`, `circle`, `ellipse`, `line`, `polyline` e `polygon`, com `fill`,
/// `stroke`, `stroke-width`, `fill-rule`, `display`, `visibility`, o atributo
/// `style` inline, herança de atributos, `transform`, `viewBox` e
/// `preserveAspectRatio`.
///
/// Ainda fora do alcance, com os elementos correspondentes simplesmente
/// ignorados: texto, imagens, `use`, gradientes, padrões, máscaras, recortes
/// por `clip-path`, marcadores e folhas de estilo em `<style>`.
///
/// `stroke-dasharray` não é emitido por causa de um defeito no canvas do
/// kernel, e as opacidades parciais exigem um ExtGState — logo, só saem
/// quando o canvas pertence a um documento. Ambos os pontos estão anotados
/// em `renderers/impl/abstract_svg_node_renderer.dart`.
///
/// Uma unidade de usuário do SVG equivale a um pixel CSS, ou seja 0,75 pt.
/// É por isso que `<rect width="100">` sem `viewBox` mede 75 pt no PDF.
class CraftSvgConverter {
  CraftSvgConverter._();

  /// Desenha [svg] no [canvas].
  ///
  /// Sem [viewport], o desenho ocupa o tamanho intrínseco do SVG ancorado na
  /// origem do sistema de coordenadas corrente, crescendo para cima — que é
  /// o canto inferior esquerdo da página num canvas recém-criado. Para
  /// posicionar o desenho, informe explicitamente o retângulo.
  static Future<void> drawOnCanvas(String svg, CraftPdfCanvas canvas,
      {CraftRectangle? viewport}) async {
    final prepared = _prepare(svg, viewport);
    if (prepared == null) return;
    await _draw(prepared, canvas, viewport ?? prepared.intrinsicViewport);
  }

  /// Desenha [svg] numa página existente.
  ///
  /// Sem [viewport], o desenho é ancorado no canto superior esquerdo da
  /// página, que é a leitura natural de um SVG cujo eixo Y cresce para baixo.
  static Future<void> drawOnPage(String svg, CraftPdfPage page,
      {CraftRectangle? viewport}) async {
    final prepared = _prepare(svg, viewport);
    if (prepared == null) return;
    final canvas = await CraftPdfCanvas.fromPage(page);
    var area = viewport;
    if (area == null) {
      final bounds = await page.mediaBounds();
      final size = prepared.intrinsicViewport;
      area = CraftRectangle(bounds.getX(), bounds.getTop() - size.getHeight(),
          size.getWidth(), size.getHeight());
    }
    await _draw(prepared, canvas, area);
  }

  /// Gera um PDF de uma página contendo apenas [svg].
  ///
  /// Sem [pageSize] a página recebe exatamente o tamanho intrínseco do
  /// desenho, evitando margens que o chamador não pediu.
  static Future<Uint8List> convertToBytes(String svg,
      {CraftPageSize? pageSize}) async {
    final output = BytesBuilder(copy: false);
    final document =
        CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(output));
    try {
      final prepared = _prepare(svg, pageSize);
      final size = prepared?.intrinsicViewport ?? CraftRectangle(0, 0, 1, 1);
      final resolvedSize = pageSize ??
          CraftPageSize(size.getWidth() <= 0 ? 1 : size.getWidth(),
              size.getHeight() <= 0 ? 1 : size.getHeight());
      final page = await document.appendBlankPage(resolvedSize);
      if (prepared != null) {
        final canvas = await CraftPdfCanvas.fromPage(page);
        await _draw(
            prepared,
            canvas,
            CraftRectangle(0, resolvedSize.getHeight() - size.getHeight(),
                size.getWidth(), size.getHeight()));
      }
    } finally {
      await document.close();
    }
    return output.takeBytes();
  }

  static Future<void> _draw(
      _PreparedSvg prepared, CraftPdfCanvas canvas, CraftRectangle area) async {
    final context = prepared.context;
    context.pushCanvas(canvas);
    try {
      await CraftPdfRootSvgNodeRenderer(prepared.tree, area).draw(context);
    } finally {
      context.popCanvas();
    }
  }

  /// A montagem da árvore é separada do desenho porque o tamanho intrínseco
  /// só se conhece depois de resolver os atributos do elemento raiz — e ele
  /// é necessário antes de existir uma página onde desenhar.
  static _PreparedSvg? _prepare(String svg, CraftRectangle? customViewport) {
    final element = _findSvgElement(svg);
    if (element == null) return null;
    final tree = const CraftDefaultSvgProcessor().process(element);
    if (tree == null) return null;

    final context = CraftSvgDrawContext(null, null);
    context.setCustomViewport(customViewport);
    final em = context.getCssContext().getRootFontSize();
    var size = CraftSvgCssUtils.extractWidthAndHeight(tree, em, context);
    if (size.getWidth() <= 0 || size.getHeight() <= 0) {
      // Dimensão ausente ou inválida cai no viewport padrão do SVG, em vez de
      // produzir um desenho de área nula.
      size = CraftRectangle(0, 0, SvgValues.DEFAULT_VIEWPORT_WIDTH,
          SvgValues.DEFAULT_VIEWPORT_HEIGHT);
    }
    return _PreparedSvg(tree, size, context);
  }

  /// Localiza o primeiro `<svg>` do documento.
  ///
  /// O SVG é analisado pelo parser HTML5, que trata conteúdo estrangeiro
  /// segundo a especificação: preserva a caixa de nomes como `viewBox` e
  /// `clipPath`, e nunca executa nada do que encontra.
  static dom.Element? _findSvgElement(String svg) {
    final fragment = html_parser.parseFragment(svg);
    final queue = <dom.Node>[...fragment.nodes];
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      if (node is dom.Element) {
        if (node.localName == SvgTags.SVG) return node;
        queue.addAll(node.nodes);
      }
    }
    return null;
  }
}

class _PreparedSvg {
  final CraftSvgNodeRenderer tree;
  final CraftRectangle intrinsicViewport;
  final CraftSvgDrawContext context;

  const _PreparedSvg(this.tree, this.intrinsicViewport, this.context);
}
