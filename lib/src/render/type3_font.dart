import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_stream.dart';

/// A Type 3 font, ISO 32000-1 clause 9.6.5.
///
/// A Type 3 font carries no font program. Each glyph is a small content
/// stream in `/CharProcs`, named by the font's `/Encoding` `/Differences`,
/// and drawn in a glyph space that `/FontMatrix` maps into text space. That
/// makes the renderer, not a font engine, the thing that has to draw it: the
/// procedure is executed exactly like a form XObject whose matrix is the
/// font matrix composed with the text state.
///
/// Because the glyph space is arbitrary rather than the 1/1000 em that every
/// other PDF font uses, `/Widths` is in glyph space too and has to go through
/// [advance] before it can be added to the text matrix (clause 9.2.4).
class PdfType3Font {
  /// `/FontMatrix`, six numbers, glyph space to text space.
  final List<double> fontMatrix;

  /// `/CharProcs`: glyph name to the content stream that draws it.
  final PdfDictionary charProcs;

  /// `/Resources` of the font, which the glyph procedures are run against.
  /// Null falls back to the resources of the page that shows the text; a
  /// Type 3 font is allowed to omit its own (clause 9.6.5, Table 112).
  final PdfDictionary? resources;

  /// Character code to `/CharProcs` key, from `/Encoding` `/Differences`.
  final Map<int, String> codeToName;

  const PdfType3Font({
    required this.fontMatrix,
    required this.charProcs,
    required this.resources,
    required this.codeToName,
  });

  /// Reads a Type 3 font dictionary, or returns null when it is not usable.
  ///
  /// [codeToName] is the encoding table the caller already built for the
  /// font: for a Type 3 font it is the only way a code reaches a procedure,
  /// so a font whose `/Encoding` named nothing draws nothing.
  static Future<PdfType3Font?> parse(
    PdfDictionary font,
    Map<int, String> codeToName,
  ) async {
    final charProcs = await font.dictionaryEntry(PdfName('CharProcs'));
    if (charProcs == null) return null;

    final matrix = await _matrix(await font.arrayEntry(PdfName('FontMatrix')));
    // A singular font matrix collapses every glyph to nothing; refusing it
    // here keeps the renderer from building a degenerate transform later.
    if (matrix[0] * matrix[3] - matrix[1] * matrix[2] == 0) return null;

    return PdfType3Font(
      fontMatrix: matrix,
      charProcs: charProcs,
      resources: await font.dictionaryEntry(PdfName.resources),
      codeToName: codeToName,
    );
  }

  /// The default of Table 112 when `/FontMatrix` is missing or malformed is
  /// the 1/1000 glyph space every other font uses.
  static Future<List<double>> _matrix(PdfArray? array) async {
    if (array == null || array.size() != 6) {
      return const <double>[0.001, 0, 0, 0.001, 0, 0];
    }
    final out = <double>[];
    for (var i = 0; i < 6; i++) {
      final value = await array.get(i);
      out.add(value is PdfNumber ? value.doubleValue() : 0);
    }
    return out;
  }

  /// The content stream that draws [code], or null when there is none.
  Future<PdfStream?> procedure(int code) async {
    final name = codeToName[code];
    if (name == null) return null;
    return charProcs.streamEntry(PdfName(name));
  }

  /// Maps a `/Widths` entry, which is in glyph space, to the horizontal
  /// displacement in text space that clause 9.4.4 adds to the text matrix.
  ///
  /// Only the horizontal component matters: the glyph displacement is
  /// `(w, 0)` transformed by the font matrix, and the translation row of the
  /// matrix does not apply to a displacement vector.
  double advance(double glyphSpaceWidth) => glyphSpaceWidth * fontMatrix[0];
}
