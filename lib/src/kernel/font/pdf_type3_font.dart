import 'package:dpdf/src/io/font/type3_font.dart';
import 'package:dpdf/src/kernel/font/pdf_simple_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/io/font/otf/glyph.dart';

class CraftPdfType3Font extends CraftPdfSimpleFont<CraftType3Font> {
  CraftPdfType3Font(CraftPdfDictionary dictionary) : super(dictionary) {
    setFontProgram(CraftType3Font());
  }

  /// Creates a PdfType3Font from a given dictionary.
  static CraftPdfType3Font fromDictionary(CraftPdfDictionary dictionary) {
    return CraftPdfType3Font(dictionary);
  }

  @override
  Future<void> initFromDictionary(CraftPdfDictionary dictionary) async {
    final firstCharObj = await dictionary.integerEntry(CraftPdfName.firstChar);
    final lastCharObj = await dictionary.integerEntry(CraftPdfName.lastChar);
    final widthsObj = await dictionary.arrayEntry(CraftPdfName.widths);
    final fontMatrixObj = await dictionary.arrayEntry(CraftPdfName.fontMatrix);
    final charProcsObj =
        await dictionary.dictionaryEntry(CraftPdfName.charProcs);
    final bboxObj = await dictionary.arrayEntry(CraftPdfName.fontBBox);

    if (firstCharObj != null &&
        lastCharObj != null &&
        widthsObj != null &&
        fontMatrixObj != null &&
        charProcsObj != null &&
        bboxObj != null) {
      final font = getFontProgram() as CraftType3Font?;
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
  Future<void> addFontStream(CraftPdfDictionary fontDescriptor) async {
    // Type3 fonts don't use a stream in the descriptor usually, they define charProcs
  }

  @override
  CraftGlyph? getGlyph(int unicode) {
    return getFontProgram()?.getGlyphByCode(unicode);
  }
}
