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

class PdfTrueTypeFont extends PdfSimpleFont<TrueTypeFont> {
  PdfTrueTypeFont(TrueTypeFont ttf, [String? encoding, bool embedded = false])
      : super() {
    setFontProgram(ttf);
    this.embedded = embedded;

    FontNames fontNames = ttf.getFontNames();
    if (embedded && !fontNames.isAllowEmbedding()) {
      throw Exception(
          "Font ${fontNames.getFontName()} cannot be embedded due to licensing restrictions.");
    }

    if ((encoding == null || encoding.isEmpty) && ttf.getIsFontSpecific()) {
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

  PdfTrueTypeFont.fromDictionary(PdfDictionary fontDictionary)
      : super(fontDictionary) {
    newFont = false;
  }

  @override
  Glyph? getGlyph(int unicode) {
    if (fontEncoding != null && fontEncoding!.canEncode(unicode)) {
      Glyph? glyph = getFontProgram()!.getGlyph(unicode); 
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
    if (isFlushed()) return;
    ensureUnderlyingObjectHasIndirectReference();
    if (newFont) {
      PdfName subtype;
      String fontName;
      if ((getFontProgram() as TrueTypeFont).isCff()) {
        subtype = PdfName.type1;
        fontName = getFontProgram()!.getFontNames().getFontName()!;
      } else {
        subtype = PdfName.trueType;
        fontName = PdfFont.updateSubsetPrefix(
            getFontProgram()!.getFontNames().getFontName()!, subset, embedded);
      }
      await flushFontData(fontName, subtype);
    }
    await super.flush();
  }

  @override
  Future<void> addFontStream(PdfDictionary fontDescriptor) async {
    if (embedded) {
      PdfName fontFileName;
      PdfStream? fontStream;

      TrueTypeFont ttf = getFontProgram() as TrueTypeFont;
      if (ttf.isCff()) {
        fontFileName = PdfName.fontFile3;
        Uint8List? fontStreamBytes = ttf.readCffFont();
        if (fontStreamBytes != null) {
          fontStream =
              getPdfFontStream(fontStreamBytes, [fontStreamBytes.length]);
          fontStream!.put(PdfName.subtype, PdfName("Type1C"));
        }
      } else {
        fontFileName = PdfName.fontFile2;
        Set<int> glyphs = {};
        for (int k = 0; k < usedGlyphs.length; k++) {
          if (usedGlyphs[k] != 0) {
            int uni = fontEncoding!.getUnicode(k);
            Glyph? glyph =
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
        if (fontStream.getIndirectReference() != null) {
          await fontStream.flush();
        }
      }
    }
  }

  @override
  PdfDictionary getFontDescriptor(String fontName) {
    PdfDictionary fd = PdfDictionary();
    fd.put(PdfName.type, PdfName.fontDescriptor);
    fd.put(PdfName.fontName, PdfName(fontName));

    final metrics = getFontProgram()!.getFontMetrics();
    fd.put(
        PdfName.flags, PdfNumber(getFontProgram()!.getPdfFontFlags().toDouble()));
    fd.put(PdfName.fontBBox, PdfArray.fromInts(metrics.getBbox()));
    fd.put(PdfName.italicAngle, PdfNumber(metrics.getItalicAngle()));
    fd.put(PdfName.ascent, PdfNumber(metrics.getTypoAscender().toDouble()));
    fd.put(PdfName.descent, PdfNumber(metrics.getTypoDescender().toDouble()));
    fd.put(PdfName.capHeight, PdfNumber(metrics.getCapHeight().toDouble()));
    fd.put(PdfName.stemV, PdfNumber(80));

    return fd;
  }
}
