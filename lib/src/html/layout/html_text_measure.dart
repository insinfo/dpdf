import '../../editing/pdf_standard_font_metrics.dart';
import '../model/html_box.dart';
import '../paint/html_standard_font.dart';

/// Measures text with the metrics of the face the painter will actually use.
///
/// Layout and paint must agree: the painter resolves a CSS style to one of the
/// standard 14 faces through [CraftHtmlStandardFont], and this measure asks
/// that same face for its advance widths. Line breaking, centring and
/// right-alignment are therefore exact for the text that gets drawn, rather
/// than an average-character-width guess.
///
/// The painter writes text with `/WinAnsiEncoding`, so that is the encoding
/// measured here.
abstract final class CraftHtmlTextMeasure {
  static const String _encoding = 'WinAnsiEncoding';

  /// Width in points of [text] rendered in [style].
  static double text(String text, CraftHtmlTextStyle style) {
    if (text.isEmpty) return 0;
    return PdfStandardFontMetrics.textWidth(
        CraftHtmlStandardFont.resolve(style), _encoding, text, style.fontSize);
  }

  /// Width in points of a single space in [style], the gap between words.
  static double space(CraftHtmlTextStyle style) {
    return PdfStandardFontMetrics.widthOrDefault(
            CraftHtmlStandardFont.resolve(style), _encoding, 32, 278) /
        1000 *
        style.fontSize;
  }

  /// How many characters of [style] fit in [width], used where a caller needs
  /// a character budget rather than a measured string. The average advance of
  /// the face is used, so this is an estimate by construction.
  static int charactersPerLine(CraftHtmlTextStyle style, double width) {
    final average = _averageAdvance(style);
    if (average <= 0) return 1;
    return (width / average).floor().clamp(1, 10000);
  }

  static final Map<String, double> _averages = {};

  /// Mean advance of the printable ASCII range, cached per face.
  static double _averageAdvance(CraftHtmlTextStyle style) {
    final font = CraftHtmlStandardFont.resolve(style);
    final mean = _averages.putIfAbsent(font, () {
      var total = 0.0;
      var count = 0;
      for (var code = 32; code < 127; code++) {
        total +=
            PdfStandardFontMetrics.widthOrDefault(font, _encoding, code, 500);
        count++;
      }
      return total / count;
    });
    return mean / 1000 * style.fontSize;
  }
}
