import 'dart:typed_data';

import 'package:dpdf/src/io/font/font_encoding.dart';
import 'package:dpdf/src/io/font/otf/glyph.dart';
import 'package:dpdf/src/io/font/type1_font.dart';
import 'package:dpdf/src/kernel/font/pdf_simple_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';

class CraftPdfType1Font extends CraftPdfSimpleFont<CraftType1Font> {
  CraftPdfType1Font(CraftType1Font type1Font,
      [String? encoding, bool embedded = false])
      : super() {
    setFontProgram(type1Font);
    this.embedded = embedded && !type1Font.isBuiltInFont();
    if ((encoding == null || encoding.isEmpty) &&
        type1Font.getIsFontSpecific()) {
      encoding = CraftFontEncoding.FONT_SPECIFIC;
    }
    if (encoding != null &&
        encoding.toLowerCase() ==
            CraftFontEncoding.FONT_SPECIFIC.toLowerCase()) {
      fontEncoding = CraftFontEncoding.createFontSpecificEncoding();
    } else {
      fontEncoding =
          CraftFontEncoding.createFontEncoding(encoding ?? "WinAnsiEncoding");
    }
  }

  CraftPdfType1Font.fromDictionary(CraftPdfDictionary fontDictionary)
      : super(fontDictionary) {
    newFont = false;
  }

  @override
  bool isSubset() => subset;

  @override
  void setSubset(bool subset) {
    this.subset = subset;
  }

  @override
  Future<void> flush() async {
    if (hasBeenWritten()) return;
    ensureUnderlyingObjectHasIndirectReference();
    if (newFont) {
      // fontProgram is Type1Font, so getFontNames().getFontName() is available
      // But getFontName returns String?, assuming not null for simple fonts
      await flushFontData(
          fontProgram!.getFontNames().getFontName()!, CraftPdfName.type1);
    }
    await super.flush();
  }

  @override
  CraftGlyph? getGlyph(int unicode) {
    if (fontEncoding != null && fontEncoding!.canEncode(unicode)) {
      if (fontEncoding!.isFontSpecific()) {
        return getFontProgram()!.getGlyphByCode(unicode);
      } else {
        CraftGlyph? glyph = getFontProgram()!.getGlyph(unicode);
        if (glyph == null) {
          glyph = notdefGlyphs[unicode];
          if (glyph == null) {
            glyph = CraftGlyph(-1, 0, unicode);
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
    return (getFontProgram() as CraftType1Font)
        .isBuiltInFont(); // cast for now, though generic T should handle it
  }

  @override
  Future<void> addFontStream(CraftPdfDictionary fontDescriptor) async {
    if (embedded) {
      // Assuming not IDocFontProgram for now (loading from file)
      Uint8List? fontStreamBytes =
          (getFontProgram() as CraftType1Font).getFontStreamBytes();
      if (fontStreamBytes != null) {
        CraftPdfStream fontStream = CraftPdfStream.withBytes(fontStreamBytes);
        // fontStreamLengths not implemented in Type1Font yet (is just a List<int>)
        List<int>? lengths =
            (getFontProgram() as CraftType1Font).fontStreamLengths;
        if (lengths != null) {
          for (int k = 0; k < lengths.length; ++k) {
            fontStream.put(CraftPdfName("Length${k + 1}"),
                CraftPdfNumber(lengths[k].toDouble()));
          }
        }

        fontDescriptor.put(CraftPdfName.fontFile, fontStream);
        if (makeObjectIndirect(fontStream)) {
          await fontStream.flush();
        }
      }
    }
  }

  @override
  CraftPdfDictionary getFontDescriptor(String fontName) {
    CraftPdfDictionary fd = CraftPdfDictionary();
    fd.put(CraftPdfName.type, CraftPdfName.fontDescriptor);
    fd.put(CraftPdfName.fontName, CraftPdfName(fontName));

    final metrics = getFontProgram()!.getFontMetrics();
    fd.put(CraftPdfName.flags,
        CraftPdfNumber(getFontProgram()!.getPdfFontFlags().toDouble()));
    fd.put(CraftPdfName.fontBBox, CraftPdfArray.fromInts(metrics.getBbox()));
    fd.put(CraftPdfName.italicAngle, CraftPdfNumber(metrics.getItalicAngle()));
    fd.put(CraftPdfName.ascent,
        CraftPdfNumber(metrics.getTypoAscender().toDouble()));
    fd.put(CraftPdfName.descent,
        CraftPdfNumber(metrics.getTypoDescender().toDouble()));
    fd.put(CraftPdfName.capHeight,
        CraftPdfNumber(metrics.getCapHeight().toDouble()));
    fd.put(CraftPdfName.stemV, CraftPdfNumber(80));

    return fd;
  }
}
