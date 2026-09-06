import 'package:dpdf/src/io/font/type3_font.dart';
import 'package:dpdf/src/kernel/font/pdf_simple_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/io/font/otf/glyph.dart';

class PdfType3Font extends PdfSimpleFont<Type3Font> {
  PdfType3Font(PdfDictionary dictionary) : super(dictionary) {
    setFontProgram(Type3Font());
  }

  /// Creates a PdfType3Font from a given dictionary.
  static PdfType3Font fromDictionary(PdfDictionary dictionary) {
    return PdfType3Font(dictionary);
  }

  Future<void> initFromDictionary(PdfDictionary dictionary) async {
    final firstCharObj = await dictionary.getAsInt(PdfName.firstChar);
    final lastCharObj = await dictionary.getAsInt(PdfName.lastChar);
    final widthsObj = await dictionary.getAsArray(PdfName.widths);
    final fontMatrixObj = await dictionary.getAsArray(PdfName.fontMatrix);
    final charProcsObj = await dictionary.getAsDictionary(PdfName.charProcs);
    final bboxObj = await dictionary.getAsArray(PdfName.fontBBox);

    if (firstCharObj != null &&
        lastCharObj != null &&
        widthsObj != null &&
        fontMatrixObj != null &&
        charProcsObj != null &&
        bboxObj != null) {
      final font = getFontProgram() as Type3Font?;
      if (font != null) {
        font.firstChar = firstCharObj;
        font.lastChar = lastCharObj;
        font.widths = await widthsObj.toDoubleArray();
        font.fontMatrix = await fontMatrixObj.toDoubleArray();
        font.fontBBox = await bboxObj.toDoubleArray();
      }
    }
  }

  @override
  Future<void> addFontStream(PdfDictionary fontDescriptor) async {
    // Type3 fonts don't use a stream in the descriptor usually, they define charProcs
  }

  @override
  Glyph? getGlyph(int unicode) {
    return getFontProgram()?.getGlyphByCode(unicode);
  }
}
