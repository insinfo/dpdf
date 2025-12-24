import '../pdf/pdf_dictionary.dart';
import '../pdf/pdf_name.dart';
import 'pdf_font.dart';
import 'pdf_type1_font.dart';
import 'pdf_true_type_font.dart';
import '../../io/font/type1_font.dart';
import '../../io/font/constants/standard_fonts.dart';

class PdfFontFactory {
  static PdfFont createFont(String fontName) {
    if (StandardFonts.isStandardFont(fontName)) {
      return PdfType1Font(Type1Font.createBuiltInFont(fontName));
    }
    // TODO: support more fonts
    throw Exception("Font not found or not supported yet: $fontName");
  }

  static Future<PdfFont?> createFontFromDictionary(
      PdfDictionary fontDictionary) async {
    PdfName? subtype = await fontDictionary.getAsName(PdfName.subtype);
    if (PdfName.type1 == subtype) {
      return PdfType1Font.fromDictionary(fontDictionary);
    } else if (PdfName.trueType == subtype) {
      return PdfTrueTypeFont.fromDictionary(fontDictionary);
    }
    // TODO: Type0, Type3, etc.
    return null;
  }
}
