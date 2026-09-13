import 'package:dpdf/src/kernel/font/pdf_font.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_css_utils.dart';

/// Um trecho de texto já posicionado, pronto para virar operadores PDF.
///
/// Um trecho reúne o maior número possível de caracteres consecutivos: só é
/// quebrado onde a especificação exige um reposicionamento explícito, para o
/// fluxo de conteúdo não degenerar em um `Tj` por caractere.
class SvgTextRun {
  /// Nó folha que declarou este texto; é ele que sabe pintá-lo.
  final Object leaf;

  /// Caracteres do trecho.
  final String text;

  /// Fonte já resolvida para a folha.
  final PdfFont font;

  /// Corpo em pontos.
  final double fontSize;

  /// Espaçamento acrescentado depois de cada caractere, em pontos.
  final double letterSpacing;

  /// Origem da linha de base, em unidades do usuário já convertidas.
  final double x;
  final double y;

  /// Rotação do glifo em torno da própria origem, em radianos, positiva no
  /// sentido horário — que é o sentido do eixo Y do SVG.
  final double rotation;

  /// Avanço total do trecho.
  final double width;

  /// Índice do bloco de texto ("text chunk") a que o trecho pertence.
  final int chunk;

  /// Trechos cujo alinhamento já foi resolvido pelo próprio nó, como os de
  /// `<textPath>`, não recebem o deslocamento de `text-anchor`.
  final bool anchored;

  const SvgTextRun({
    required this.leaf,
    required this.text,
    required this.font,
    required this.fontSize,
    required this.letterSpacing,
    required this.x,
    required this.y,
    required this.rotation,
    required this.width,
    required this.chunk,
    this.anchored = false,
  });

  SvgTextRun shifted(double dx) => SvgTextRun(
        leaf: leaf,
        text: text,
        font: font,
        fontSize: fontSize,
        letterSpacing: letterSpacing,
        x: x + dx,
        y: y,
        rotation: rotation,
        width: width,
        chunk: chunk,
        anchored: anchored,
      );
}

/// Ajuste de posição que a SVG 1.1 §10.4 atribui a um caractere.
class SvgTextCharAdjustment {
  /// Posição absoluta, quando o atributo `x`/`y` forneceu um valor para este
  /// caractere.
  final double? x;
  final double? y;

  /// Deslocamentos relativos de `dx`/`dy`.
  final double dx;
  final double dy;

  /// Rotação suplementar em radianos, se `rotate` cobriu este caractere.
  final double? rotation;

  const SvgTextCharAdjustment(this.x, this.y, this.dx, this.dy, this.rotation);

  bool get repositions => x != null || y != null || dx != 0 || dy != 0;
}

/// Listas `x`, `y`, `dx`, `dy` e `rotate` declaradas por um elemento de texto.
///
/// O índice avança a cada caractere do elemento, inclusive os que vêm de
/// descendentes, como manda a §10.4.
class SvgTextPositionProvider {
  final List<double> x;
  final List<double> y;
  final List<double> dx;
  final List<double> dy;
  final List<double> rotate;
  int index = 0;

  SvgTextPositionProvider({
    this.x = const [],
    this.y = const [],
    this.dx = const [],
    this.dy = const [],
    this.rotate = const [],
  });

  double? xAt() => index < x.length ? x[index] : null;
  double? yAt() => index < y.length ? y[index] : null;
  double? dxAt() => index < dx.length ? dx[index] : null;
  double? dyAt() => index < dy.length ? dy[index] : null;

  /// O último valor de `rotate` vale para todos os caracteres restantes.
  double? rotateAt() {
    if (rotate.isEmpty) return null;
    return rotate[index < rotate.length ? index : rotate.length - 1];
  }
}

/// Estado compartilhado por toda a montagem de um elemento `<text>`.
class SvgTextLayout {
  /// Posição corrente do texto, em unidades do usuário convertidas.
  double x = 0;
  double y = 0;

  /// Bloco de texto corrente. Cada posição absoluta abre um novo.
  int chunk = 0;

  final List<SvgTextRun> runs = [];
  final List<SvgTextPositionProvider> _providers = [];

  void pushProvider(SvgTextPositionProvider provider) =>
      _providers.add(provider);

  void popProvider() => _providers.removeLast();

  /// Abre um novo bloco de texto, usado por `<textPath>` e por toda posição
  /// absoluta.
  void startChunk() => chunk++;

  /// Consome um caractere, devolvendo o ajuste que o elemento mais interno
  /// com valor disponível impõe a ele.
  SvgTextCharAdjustment consumeChar() {
    double? absoluteX;
    double? absoluteY;
    double dx = 0;
    double dy = 0;
    double? rotation;
    var hasX = false, hasY = false, hasDx = false, hasDy = false;
    var hasRotation = false;
    for (var i = _providers.length - 1; i >= 0; i--) {
      final provider = _providers[i];
      if (!hasX) {
        final value = provider.xAt();
        if (value != null) {
          absoluteX = value;
          hasX = true;
        }
      }
      if (!hasY) {
        final value = provider.yAt();
        if (value != null) {
          absoluteY = value;
          hasY = true;
        }
      }
      if (!hasDx) {
        final value = provider.dxAt();
        if (value != null) {
          dx = value;
          hasDx = true;
        }
      }
      if (!hasDy) {
        final value = provider.dyAt();
        if (value != null) {
          dy = value;
          hasDy = true;
        }
      }
      if (!hasRotation) {
        final value = provider.rotateAt();
        if (value != null) {
          rotation = value;
          hasRotation = true;
        }
      }
    }
    for (final provider in _providers) {
      provider.index++;
    }
    return SvgTextCharAdjustment(absoluteX, absoluteY, dx, dy, rotation);
  }

  /// Aplica `text-anchor` a cada bloco de texto (SVG 1.1 §10.9.1).
  ///
  /// O deslocamento é medido do início do bloco até o fim do seu avanço, de
  /// modo que `middle` centraliza e `end` encosta o fim do texto no ponto
  /// declarado.
  void applyAnchors(String Function(Object leaf) anchorOf) {
    final byChunk = <int, List<int>>{};
    for (var i = 0; i < runs.length; i++) {
      if (runs[i].anchored) continue;
      byChunk.putIfAbsent(runs[i].chunk, () => []).add(i);
    }
    byChunk.forEach((_, indexes) {
      final anchor = anchorOf(runs[indexes.first].leaf).trim().toLowerCase();
      if (anchor != SvgValues.TEXT_ANCHOR_MIDDLE &&
          anchor != SvgValues.TEXT_ANCHOR_END) {
        return;
      }
      var start = runs[indexes.first].x;
      var end = start;
      for (final index in indexes) {
        final run = runs[index];
        if (run.x < start) start = run.x;
        if (run.x + run.width > end) end = run.x + run.width;
      }
      final advance = end - start;
      final shift =
          anchor == SvgValues.TEXT_ANCHOR_MIDDLE ? -advance / 2 : -advance;
      if (shift == 0) return;
      for (final index in indexes) {
        runs[index] = runs[index].shifted(shift);
      }
    });
  }
}

/// Converte listas de comprimentos de atributos de texto.
class SvgTextLists {
  SvgTextLists._();

  /// Lê uma lista de números separados por vírgula ou espaço, convertendo
  /// cada item com [convert].
  static List<double> parse(String? raw, double Function(String) convert) {
    if (raw == null) return const [];
    final parts = SvgCssUtils.splitValueList(raw);
    if (parts.isEmpty) return const [];
    return [for (final part in parts) convert(part)];
  }

  /// Lê `rotate`, cujos valores são graus e viram radianos.
  static List<double> parseAngles(String? raw) {
    if (raw == null) return const [];
    final parts = SvgCssUtils.splitValueList(raw);
    return [
      for (final part in parts)
        (double.tryParse(part) ?? 0) * 3.141592653589793 / 180.0
    ];
  }
}

/// Um nó que participa da montagem de um elemento `<text>`.
///
/// Existe para quebrar a dependência circular entre este módulo e os
/// renderizadores de texto: a montagem só precisa saber pedir que o nó se
/// acrescente ao layout.
abstract class SvgTextLayoutNode {
  Future<void> layoutText(SvgTextLayout layout, SvgDrawContext context);
}
