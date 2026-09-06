import 'package:dpdf/src/io/font/font_program.dart';
import 'package:dpdf/src/io/font/font_program_factory.dart';

import '../pdf/pdf_dictionary.dart';
import '../pdf/pdf_name.dart';
import 'pdf_font.dart';
import 'pdf_type1_font.dart';
import 'pdf_true_type_font.dart';
import 'pdf_type0_font.dart';
import '../../io/font/type1_font.dart';
import '../../io/font/true_type_font.dart';
import '../../io/font/cid_font.dart';
import '../../io/font/cid_font_properties.dart';
import 'pdf_type3_font.dart';

class PdfFontFactory {
  static PdfFont createFont(String fontName,
      [String? encoding, bool embedded = false]) {
    FontProgram fontProgram = FontProgramFactory.createFont(fontName);
    if (fontProgram is TrueTypeFont) {
      if (encoding == null ||
          encoding == "Identity-H" ||
          encoding == "Identity-V") {
        return PdfType0Font(fontProgram, encoding ?? "Identity-H");
      }
      return PdfTrueTypeFont(fontProgram, encoding, embedded);
    } else if (fontProgram is Type1Font) {
      return PdfType1Font(fontProgram, encoding, embedded);
    } else if (fontProgram is CidFont) {
      return PdfType0Font(fontProgram, encoding ?? "Identity-H");
    }
    throw Exception(
        "Unsupported font program type: ${fontProgram.runtimeType}");
  }

  static Future<PdfFont?> createFontFromDictionary(
      PdfDictionary fontDictionary) async {
    PdfName? subtype = await fontDictionary.getAsName(PdfName.subtype);
    PdfFont? font;
    if (PdfName.type1 == subtype) {
      font = PdfType1Font.fromDictionary(fontDictionary);
    } else if (PdfName.trueType == subtype) {
      font = PdfTrueTypeFont.fromDictionary(fontDictionary);
    } else if (PdfName.type0 == subtype) {
      font = PdfType0Font.fromDictionary(fontDictionary);
    } else if (PdfName.type3 == subtype) {
      font = PdfType3Font.fromDictionary(fontDictionary);
    }

    if (font != null) {
      await font.initFromDictionary(fontDictionary);
    }

    return font;
  }

  static PdfFont createCjkFont(String fontName, String cmap) {
    CidFont cidFont = CidFont(fontName, cmap);
    return PdfType0Font(cidFont, cmap);
  }

  static bool isCjkFont(String fontName) {
    return CidFontProperties.isCjkFont(fontName);
  }
}
