import 'dart:typed_data';
import 'package:dpdf/src/io/font/font_encoding.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/io/font/otf/glyph.dart';
import 'package:dpdf/src/io/font/font_names.dart';
import 'package:dpdf/src/kernel/font/pdf_font.dart';
import 'package:dpdf/src/kernel/font/pdf_simple_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';

class CraftPdfTrueTypeFont extends CraftPdfSimpleFont<CraftTrueTypeFont> {
  CraftPdfTrueTypeFont(CraftTrueTypeFont ttf,
      [String? encoding, bool embedded = false])
      : super() {
    setFontProgram(ttf);
    this.embedded = embedded;

    CraftFontNames fontNames = ttf.getFontNames();
    if (embedded && !fontNames.isAllowEmbedding()) {
      throw Exception(
          "Font ${fontNames.getFontName()} cannot be embedded due to licensing restrictions.");
    }

    if ((encoding == null || encoding.isEmpty) && ttf.getIsFontSpecific()) {
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

  CraftPdfTrueTypeFont.fromDictionary(CraftPdfDictionary fontDictionary)
      : super(fontDictionary) {
    newFont = false;
  }

  @override
  CraftGlyph? getGlyph(int unicode) {
    if (fontEncoding != null && fontEncoding!.canEncode(unicode)) {
      CraftGlyph? glyph = getFontProgram()!.getGlyph(unicode);
      return glyph;
    }
    return null;
  }

  @override
  bool containsGlyph(int unicode) {
    if (fontEncoding != null) {
      if (fontEncoding!.isFontSpecific()) {
        return getFontProgram()!.getGlyphByCode(unicode) != null;
      } else {
        return fontEncoding!.canEncode(unicode) &&
            getFontProgram()!
                    .getGlyph(fontEncoding!.getUnicodeDifference(unicode)) !=
                null;
      }
    }
    return false;
  }

  @override
  Future<void> flush() async {
    if (hasBeenWritten()) return;
    ensureUnderlyingObjectHasIndirectReference();
    if (newFont) {
      CraftPdfName subtype;
      String fontName;
      if ((getFontProgram() as CraftTrueTypeFont).isCff()) {
        subtype = CraftPdfName.type1;
        fontName = getFontProgram()!.getFontNames().getFontName()!;
      } else {
        subtype = CraftPdfName.trueType;
        fontName = CraftPdfFont.updateSubsetPrefix(
            getFontProgram()!.getFontNames().getFontName()!, subset, embedded);
      }
      await flushFontData(fontName, subtype);
    }
    await super.flush();
  }

  @override
  Future<void> addFontStream(CraftPdfDictionary fontDescriptor) async {
    if (embedded) {
      CraftPdfName fontFileName;
      CraftPdfStream? fontStream;

      CraftTrueTypeFont ttf = getFontProgram() as CraftTrueTypeFont;
      if (ttf.isCff()) {
        fontFileName = CraftPdfName.fontFile3;
        Uint8List? fontStreamBytes = ttf.readCffFont();
        if (fontStreamBytes != null) {
          fontStream =
              getPdfFontStream(fontStreamBytes, [fontStreamBytes.length]);
          fontStream!.put(CraftPdfName.subtype, CraftPdfName("Type1C"));
        }
      } else {
        fontFileName = CraftPdfName.fontFile2;
        Set<int> glyphs = {};
        for (int k = 0; k < usedGlyphs.length; k++) {
          if (usedGlyphs[k] != 0) {
            int uni = fontEncoding!.getUnicode(k);
            CraftGlyph? glyph =
                (uni > -1) ? ttf.getGlyph(uni) : ttf.getGlyphByCode(k);
            if (glyph != null) {
              glyphs.add(glyph.getCode());
            }
          }
        }
        ttf.updateUsedGlyphs(glyphs, subset, subsetRanges);

        Uint8List? fontStreamBytes;
        if (subset || ttf.getDirectoryOffset() > 0) {
          fontStreamBytes = ttf.getSubset(glyphs, subset);
        } else {
          fontStreamBytes = ttf.getFontStreamBytes();
        }

        if (fontStreamBytes != null) {
          fontStream =
              getPdfFontStream(fontStreamBytes, [fontStreamBytes.length]);
        }
      }

      if (fontStream != null) {
        fontDescriptor.put(fontFileName, fontStream);
        if (fontStream.indirectHandle() != null) {
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
