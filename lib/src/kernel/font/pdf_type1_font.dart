import 'dart:typed_data';

import 'package:dpdf/src/io/font/font_encoding.dart';
import 'package:dpdf/src/io/font/otf/glyph.dart';
import 'package:dpdf/src/io/font/type1_font.dart';
import 'package:dpdf/src/kernel/font/pdf_simple_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';

class PdfType1Font extends PdfSimpleFont<Type1Font> {
  PdfType1Font(Type1Font type1Font, [String? encoding, bool embedded = false])
      : super() {
    setFontProgram(type1Font);
    this.embedded = embedded && !type1Font.isBuiltInFont();
    if ((encoding == null || encoding.isEmpty) &&
        type1Font.getIsFontSpecific()) {
      encoding = FontEncoding.FONT_SPECIFIC;
    }
    if (encoding != null &&
        encoding.toLowerCase() == FontEncoding.FONT_SPECIFIC.toLowerCase()) {
      fontEncoding = FontEncoding.createFontSpecificEncoding();
    } else {
      fontEncoding =
          FontEncoding.createFontEncoding(encoding ?? "WinAnsiEncoding");
    }
  }

  @override
  bool isSubset() => subset;

  @override
  void setSubset(bool subset) {
    this.subset = subset;
  }

  @override
  void flush() {
    if (isFlushed()) return;
    ensureUnderlyingObjectHasIndirectReference();
    if (newFont) {
      // fontProgram is Type1Font, so getFontNames().getFontName() is available
      // But getFontName returns String?, assuming not null for simple fonts
      flushFontData(fontProgram!.getFontNames().getFontName()!, PdfName.type1);
    }
    super.flush();
  }

  @override
  Glyph? getGlyph(int unicode) {
    if (fontEncoding != null && fontEncoding!.canEncode(unicode)) {
      if (fontEncoding!.isFontSpecific()) {
        return getFontProgram()!.getGlyphByCode(unicode);
      } else {
        int diff = fontEncoding!.getUnicodeDifference(unicode);
        Glyph? glyph = getFontProgram()!.getGlyph(diff);
        if (glyph == null) {
          glyph = notdefGlyphs[unicode];
          if (glyph == null) {
            glyph = Glyph(-1, 0, unicode);
            notdefGlyphs[unicode] = glyph;
          }
        }
        return glyph;
      }
    }
    return null;
  }

  @override
  bool containsGlyph(int unicode) {
    if (fontEncoding != null && fontEncoding!.canEncode(unicode)) {
      if (fontEncoding!.isFontSpecific()) {
        return getFontProgram()!.getGlyphByCode(unicode) != null;
      } else {
        return getFontProgram()!
                .getGlyph(fontEncoding!.getUnicodeDifference(unicode)) !=
            null;
      }
    }
    return false;
  }

  @override
  bool isBuiltInFont() {
    return (getFontProgram() as Type1Font)
        .isBuiltInFont(); // cast for now, though generic T should handle it
  }

  @override
  void addFontStream(PdfDictionary fontDescriptor) {
    if (embedded) {
      // Assuming not IDocFontProgram for now (loading from file)
      Uint8List? fontStreamBytes =
          (getFontProgram() as Type1Font).getFontStreamBytes();
      if (fontStreamBytes != null) {
        PdfStream fontStream = PdfStream.withBytes(fontStreamBytes);
        // fontStreamLengths not implemented in Type1Font yet (is just a List<int>)
        List<int>? lengths = (getFontProgram() as Type1Font).fontStreamLengths;
        if (lengths != null) {
          for (int k = 0; k < lengths.length; ++k) {
            fontStream.put(
                PdfName("Length${k + 1}"), PdfNumber(lengths[k].toDouble()));
          }
        }

        fontDescriptor.put(PdfName.fontFile, fontStream);
        if (makeObjectIndirect(fontStream)) {
          fontStream.flush();
        }
      }
    }
  }
}
