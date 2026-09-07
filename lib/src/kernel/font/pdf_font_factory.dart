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

class CraftPdfFontFactory {
  static CraftPdfFont createFont(String fontName,
      [String? encoding, bool embedded = false]) {
    CraftFontProgram fontProgram = CraftFontProgramFactory.createFont(fontName);
    if (fontProgram is CraftTrueTypeFont) {
      if (encoding == null ||
          encoding == "Identity-H" ||
          encoding == "Identity-V") {
        return CraftPdfType0Font(fontProgram, encoding ?? "Identity-H");
      }
      return CraftPdfTrueTypeFont(fontProgram, encoding, embedded);
    } else if (fontProgram is CraftType1Font) {
      return CraftPdfType1Font(fontProgram, encoding, embedded);
    } else if (fontProgram is CraftCidFont) {
      return CraftPdfType0Font(fontProgram, encoding ?? "Identity-H");
    }
    throw Exception(
        "Unsupported font program type: ${fontProgram.runtimeType}");
  }

  static Future<CraftPdfFont?> createFontFromDictionary(
      CraftPdfDictionary fontDictionary) async {
    CraftPdfName? subtype =
        await fontDictionary.nameEntry(CraftPdfName.subtype);
    CraftPdfFont? font;
    if (CraftPdfName.type1 == subtype) {
      font = CraftPdfType1Font.fromDictionary(fontDictionary);
    } else if (CraftPdfName.trueType == subtype) {
      font = CraftPdfTrueTypeFont.fromDictionary(fontDictionary);
    } else if (CraftPdfName.type0 == subtype) {
      font = CraftPdfType0Font.fromDictionary(fontDictionary);
    } else if (CraftPdfName.type3 == subtype) {
      font = CraftPdfType3Font.fromDictionary(fontDictionary);
    }

    if (font != null) {
      await font.initFromDictionary(fontDictionary);
    }

    return font;
  }

  static CraftPdfFont createCjkFont(String fontName, String cmap) {
    CraftCidFont cidFont = CraftCidFont(fontName, cmap);
    return CraftPdfType0Font(cidFont, cmap);
  }

  static bool isCjkFont(String fontName) {
    return CraftCidFontProperties.isCjkFont(fontName);
  }
}
