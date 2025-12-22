import 'package:dpdf/src/kernel/font/pdf_font.dart';
import 'package:dpdf/src/kernel/font/pdf_type1_font.dart';
import 'package:dpdf/src/io/font/type1_font.dart';
import 'package:dpdf/src/io/font/constants/standard_fonts.dart';

class PdfFontFactory {
  static PdfFont createFont(String fontName) {
    if (StandardFonts.isStandardFont(fontName)) {
      return PdfType1Font(Type1Font.createBuiltInFont(fontName));
    }
    throw Exception("Font not found or not supported yet: $fontName");
  }
}
