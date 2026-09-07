import '../model/html_box.dart';
import '../../io/resources/embedded_font_resources.dart';

/// Maps the portable CSS font profile to PDF standard faces.
///
/// No host font is discovered or loaded. An unknown CSS family falls back to
/// Helvetica, a face every conforming PDF viewer supplies.
class HtmlStandardFont {
  HtmlStandardFont._();

  static String resolve(HtmlTextStyle style) {
    late String candidate;
    switch (_family(style.fontFamily)) {
      case 'Courier':
        candidate = style.bold && style.italic
            ? 'Courier-BoldOblique'
            : style.bold
                ? 'Courier-Bold'
                : style.italic
                    ? 'Courier-Oblique'
                    : 'Courier';
        break;
      case 'Times-Roman':
        candidate = style.bold && style.italic
            ? 'Times-BoldItalic'
            : style.bold
                ? 'Times-Bold'
                : style.italic
                    ? 'Times-Italic'
                    : 'Times-Roman';
        break;
      default:
        candidate = style.bold && style.italic
            ? 'Helvetica-BoldOblique'
            : style.bold
                ? 'Helvetica-Bold'
                : style.italic
                    ? 'Helvetica-Oblique'
                    : 'Helvetica';
    }
    // The PDF base-font name alone is not enough: this pure-Dart build must
    // also have the AFM needed by its writer. Do not choose a face that would
    // fail while producing the document.
    return EmbeddedFontResources.hasMetrics(candidate)
        ? candidate
        : 'Helvetica';
  }

  static String _family(String? source) {
    if (source == null) return 'Helvetica';
    for (final candidate in _families(source)) {
      final name = candidate.toLowerCase();
      if (name == 'courier' || name == 'monospace') return 'Courier';
      if (name == 'times' || name == 'times new roman' || name == 'serif') {
        return 'Times-Roman';
      }
      if (name == 'helvetica' ||
          name == 'arial' ||
          name == 'sans-serif' ||
          name == 'sans serif') {
        return 'Helvetica';
      }
    }
    return 'Helvetica';
  }

  /// Splits a CSS family list without treating quoted commas as separators.
  static Iterable<String> _families(String source) sync* {
    var quote = 0;
    var start = 0;
    for (var index = 0; index <= source.length; index++) {
      final code = index == source.length ? 44 : source.codeUnitAt(index);
      if ((code == 34 || code == 39) && (quote == 0 || quote == code)) {
        quote = quote == 0 ? code : 0;
      } else if (code == 44 && quote == 0) {
        var value = source.substring(start, index).trim();
        if (value.length >= 2) {
          final first = value.codeUnitAt(0);
          final last = value.codeUnitAt(value.length - 1);
          if ((first == 34 || first == 39) && first == last) {
            value = value.substring(1, value.length - 1);
          }
        }
        if (value.isNotEmpty) yield value;
        start = index + 1;
      }
    }
  }
}
