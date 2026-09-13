import 'dart:math' as math;

import 'package:dgfx/dgfx.dart';
import 'package:dpdf/src/io/font/constants/standard_fonts.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/kernel/font/pdf_font.dart';
import 'package:dpdf/src/kernel/font/pdf_font_factory.dart';
import 'package:dpdf/src/kernel/font/pdf_type0_font.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_text_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_text_layout.dart';

/// Contêiner de `<text>` ou `<tspan>` (SVG 1.1, capítulo 10).
///
/// O elemento raiz monta o layout inteiro antes de escrever qualquer
/// operador: `text-anchor` só pode ser resolvido depois de conhecido o avanço
/// completo de cada bloco de texto, e a mesma passagem resolve as listas de
/// `x`, `y`, `dx`, `dy` e `rotate`. Os `<tspan>` não desenham por conta
/// própria; eles contribuem posições e propriedades para essa montagem.
class TextSvgNodeRenderer extends AbstractBranchSvgNodeRenderer
    implements SvgTextNodeRenderer, SvgTextLayoutNode {
  final bool root;
  TextSvgNodeRenderer({this.root = false});

  @override
  Future<void> draw(SvgDrawContext context) async {
    // Um `<tspan>` só existe dentro da montagem conduzida pelo `<text>`; ser
    // alcançado pelo percurso comum de desenho significaria desenhá-lo duas
    // vezes, fora do bloco de texto a que pertence.
    if (!root) return;
    await super.draw(context);
  }

  @override
  Future<void> doDraw(SvgDrawContext context) async {
    final canvas = context.getCurrentCanvas();
    // Texto exige uma fonte no dicionário de recursos, que por sua vez exige
    // um documento. Desenhar num canvas solto continua sendo legítimo para o
    // resto do módulo, então aqui o texto é apenas omitido.
    if (canvas.resources == null || canvas.getDocument() == null) return;

    final layout = SvgTextLayout();
    await layoutText(layout, context);
    layout.applyAnchors(_anchorOf);
    // O cursor herdado pelo próximo elemento de texto continua onde este
    // parou, como esperam os chamadores que compõem várias linhas.
    context.resetTextMove();
    context.addTextMove(layout.x, layout.y);
    for (final run in layout.runs) {
      final leaf = run.leaf;
      if (leaf is TextLeafSvgNodeRenderer) await leaf.drawRun(context, run);
    }
  }

  static String _anchorOf(Object leaf) {
    if (leaf is AbstractSvgNodeRenderer) {
      return leaf.getAttributeOrDefault(
          SvgAttributes.TEXT_ANCHOR, SvgValues.TEXT_ANCHOR_START);
    }
    return SvgValues.TEXT_ANCHOR_START;
  }

  @override
  Future<void> layoutText(SvgTextLayout layout, SvgDrawContext context) async {
    if (isHidden()) return;
    layout.pushProvider(SvgTextPositionProvider(
      x: SvgTextLists.parse(getAttribute(SvgAttributes.X),
          (value) => parseHorizontalLength(value, context)),
      y: SvgTextLists.parse(getAttribute(SvgAttributes.Y),
          (value) => parseVerticalLength(value, context)),
      dx: SvgTextLists.parse(getAttribute(SvgAttributes.DX),
          (value) => parseHorizontalLength(value, context)),
      dy: SvgTextLists.parse(getAttribute(SvgAttributes.DY),
          (value) => parseVerticalLength(value, context)),
      rotate: SvgTextLists.parseAngles(getAttribute(SvgAttributes.ROTATE)),
    ));
    try {
      for (final child in getChildren()) {
        if (child is SvgTextLayoutNode) {
          await (child as SvgTextLayoutNode).layoutText(layout, context);
        }
      }
    } finally {
      layout.popProvider();
    }
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = TextSvgNodeRenderer(root: root);
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}

/// Nó sintético que carrega o texto literal de um elemento de texto.
class TextLeafSvgNodeRenderer extends AbstractSvgNodeRenderer
    implements SvgTextNodeRenderer, SvgTextLayoutNode {
  /// A resolução de fonte é assíncrona e pode ler um arquivo; guardá-la evita
  /// repeti-la entre a montagem e o desenho do mesmo trecho.
  PdfFont? _font;

  @override
  Future<void> doDraw(SvgDrawContext context) async {}

  @override
  Future<void> layoutText(SvgTextLayout layout, SvgDrawContext context) async {
    if (isHidden()) return;
    final text = getAttribute(SvgTextLeafAttributes.text) ?? '';
    if (text.isEmpty) return;

    final fontSize = getCurrentFontSize(context);
    final font = await resolveFont(context);
    final letterSpacing = _spacing(SvgAttributes.LETTER_SPACING, context);
    final wordSpacing = _spacing(SvgAttributes.WORD_SPACING, context);

    final buffer = StringBuffer();
    var open = false;
    var runX = 0.0, runY = 0.0, runWidth = 0.0, runRotation = 0.0;
    var runChunk = 0;

    void flush() {
      if (open && buffer.isNotEmpty) {
        layout.runs.add(SvgTextRun(
          leaf: this,
          text: buffer.toString(),
          font: font,
          fontSize: fontSize,
          letterSpacing: letterSpacing,
          x: runX,
          y: runY,
          rotation: runRotation,
          width: runWidth,
          chunk: runChunk,
        ));
      }
      buffer.clear();
      open = false;
    }

    // Espaçamento entre palavras é aplicado reposicionando a palavra
    // seguinte: o operador `Tw` do PDF não alcança fontes compostas de dois
    // bytes (ISO 32000-1, 9.3.3), que é o caso de toda fonte incorporada aqui.
    var breakAfterSpace = false;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final adjustment = layout.consumeChar();
      if (adjustment.x != null) layout.x = adjustment.x!;
      if (adjustment.y != null) layout.y = adjustment.y!;
      layout.x += adjustment.dx;
      layout.y += adjustment.dy;
      // Só a posição absoluta horizontal abre um novo bloco de texto na
      // escrita horizontal (§10.9.1).
      if (adjustment.x != null) layout.startChunk();
      final rotation = adjustment.rotation ?? 0;
      if (open &&
          (adjustment.repositions ||
              rotation != 0 ||
              rotation != runRotation ||
              breakAfterSpace)) {
        flush();
      }
      if (!open) {
        runX = layout.x;
        runY = layout.y;
        runWidth = 0;
        runRotation = rotation;
        runChunk = layout.chunk;
        open = true;
      }
      var advance = font.getWidthPoint(char, fontSize) + letterSpacing;
      if (char == ' ') advance += wordSpacing;
      buffer.write(char);
      runWidth += advance;
      layout.x += advance;
      breakAfterSpace = wordSpacing != 0 && char == ' ';
    }
    flush();
  }

  /// Emite um trecho já posicionado.
  Future<void> drawRun(SvgDrawContext context, SvgTextRun run) async {
    final canvas = context.getCurrentCanvas();
    canvas.saveState();
    try {
      await preDraw(context);
      canvas.beginText();
      await canvas.setFontAndSize(run.font, run.fontSize);
      if (run.letterSpacing != 0) {
        canvas.setCharacterSpacing(run.letterSpacing);
      }
      final mode = _textRenderingMode();
      if (mode != 0) canvas.setTextRenderingMode(mode);
      // A raiz do SVG inverte o eixo Y do canvas, então o espaço geométrico
      // cresce para baixo. A matriz de texto desfaz essa inversão em torno da
      // linha de base pedida e, quando `rotate` pede, gira o glifo no sentido
      // horário, que é o sentido positivo do SVG.
      final cos = math.cos(run.rotation);
      final sin = math.sin(run.rotation);
      canvas.setTextMatrix(cos, sin, sin, -cos, run.x, run.y);
      canvas.showText(run.text);
      canvas.endText();
      _drawDecoration(context, run);
    } finally {
      canvas.restoreState();
    }
  }

  /// Modo de renderização de texto do PDF (ISO 32000-1, 9.3.6): preencher,
  /// traçar ou ambos, conforme `fill` e `stroke` do SVG.
  int _textRenderingMode() {
    if (doStroke && doFill) return 2;
    if (doStroke) return 1;
    return 0;
  }

  /// Desenha `text-decoration` (§10.12) como barras preenchidas com a cor de
  /// preenchimento corrente.
  ///
  /// Trechos girados são deixados sem decoração: a barra teria de acompanhar
  /// a rotação de cada glifo e deixaria de ser uma linha contínua.
  void _drawDecoration(SvgDrawContext context, SvgTextRun run) {
    final raw = getAttribute(SvgAttributes.TEXT_DECORATION);
    if (raw == null || run.rotation != 0 || run.width <= 0) return;
    final tokens = raw
        .toLowerCase()
        .split(RegExp(r'[\s,]+'))
        .where((token) => token.isNotEmpty)
        .toSet();
    if (tokens.isEmpty || tokens.contains(SvgValues.NONE)) return;

    final metrics = run.font.getFontProgram()?.getFontMetrics();
    final thickness = (metrics == null || metrics.getUnderlineThickness() == 0
            ? 50
            : metrics.getUnderlineThickness()) /
        1000.0 *
        run.fontSize;
    final ascender = (metrics?.getTypoAscender() ?? 800) / 1000.0;
    final underline = -(metrics?.getUnderlinePosition() ?? -100) / 1000.0;
    final strikeout = metrics == null || metrics.getStrikeoutPosition() == 0
        ? -ascender * 0.4
        : -metrics.getStrikeoutPosition() / 1000.0;

    final canvas = context.getCurrentCanvas();
    for (final token in tokens) {
      double? offset;
      if (token == SvgValues.UNDERLINE) {
        offset = underline;
      } else if (token == SvgValues.OVERLINE) {
        offset = -ascender;
      } else if (token == SvgValues.LINE_THROUGH) {
        offset = strikeout;
      }
      if (offset == null) continue;
      canvas
          .rectangle(run.x, run.y + offset * run.fontSize - thickness / 2,
              run.width, thickness)
          .fill();
    }
  }

  double _spacing(String attribute, SvgDrawContext context) {
    final raw = getAttribute(attribute);
    if (raw == null) return 0;
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized == 'normal' ||
        normalized == 'inherit' ||
        normalized == SvgValues.NONE) {
      return 0;
    }
    return parseHorizontalLength(raw, context);
  }

  /// Resolve a fonte declarada, com memória entre montagem e desenho.
  Future<PdfFont> resolveFont(SvgDrawContext context) async {
    final cached = _font;
    if (cached != null) return cached;
    final resolved = await _resolveFont(context);
    _font = resolved;
    return resolved;
  }

  Future<PdfFont> _resolveFont(SvgDrawContext context) async {
    final collection = context.fontCollection;
    if (collection != null) {
      final families = (getAttribute(SvgAttributes.FONT_FAMILY) ?? '')
          .split(',')
          .map((v) => v.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), ''))
          .where((v) => v.isNotEmpty)
          .toList();
      final weightRaw = getAttribute(SvgAttributes.FONT_WEIGHT) ?? '400';
      final weight = int.tryParse(weightRaw) ??
          (weightRaw.toLowerCase() == 'bold' ? 700 : 400);
      final style =
          (getAttribute(SvgAttributes.FONT_STYLE) ?? '').toLowerCase();
      final slant = style == 'italic'
          ? BLFontSlant.italic
          : style == 'oblique'
              ? BLFontSlant.oblique
              : BLFontSlant.normal;
      final face = await collection.resolve(BLFontQuery(
          families.isEmpty ? const ['sans-serif'] : families,
          weight: weight,
          slant: slant));
      if (face != null && face.hasTrueTypeOutlines) {
        try {
          return PdfType0Font(TrueTypeFont.fromBytes(face.data), 'Identity-H');
        } on Object {
          // O incorporador PDF pode aceitar menos formatos que o dgfx.
        }
      }
    }
    return PdfFontFactory.createFont(StandardFonts.HELVETICA);
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = TextLeafSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}

/// Chaves sintéticas usadas pelos nós de texto.
class SvgTextLeafAttributes {
  SvgTextLeafAttributes._();

  /// Onde o processador guarda o texto literal do nó.
  static const String text = '_text';
}
