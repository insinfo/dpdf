import 'dart:typed_data';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/io/font/font_program.dart';
import 'package:dpdf/src/io/font/otf/glyph.dart';
import 'package:dpdf/src/io/font/cmap_encoding.dart';
import 'package:dpdf/src/kernel/font/pdf_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_output_stream.dart';
import 'package:dpdf/src/io/font/otf/glyph_line.dart';
import 'package:dpdf/src/io/util/text_util.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'font_util.dart';
import 'cpdf_tounicodemap.dart';
import 'cpdf_fontglobals.dart';
import 'cpdf_cid2unicodemap.dart';

class PdfType0Font extends PdfFont {
  late CMapEncoding cmapEncoding;
  bool vertical = false;
  Map<int, Glyph> utilizedGlyphs = {};
  CPDF_ToUnicodeMap? toUnicode;
  CPDF_CID2UnicodeMap? cid2unicode;

  PdfType0Font(FontProgram fontProgram, [String cmap = "Identity-H"])
      : super() {
    this.fontProgram = fontProgram;
    this.embedded = true;
    vertical = cmap.endsWith("V");
    cmapEncoding = CMapEncoding(cmap);
  }

  PdfType0Font.fromDictionary(PdfDictionary fontDictionary)
      : super(fontDictionary) {
    newFont = false;
  }

  @override
  Future<void> initFromDictionary(PdfDictionary fontDictionary) async {
    PdfObject? encoding = await fontDictionary.get(PdfName.encoding);
    if (encoding is PdfName) {
      cmapEncoding = CMapEncoding(encoding.getValue());
    } else if (encoding is PdfStream) {
      Uint8List? bytes = await encoding.getBytes();
      if (bytes != null) {
        cmapEncoding = CMapEncoding.fromBytes("", bytes);
      } else {
        cmapEncoding = CMapEncoding("Identity-H");
      }
    } else {
      cmapEncoding = CMapEncoding("Identity-H");
    }

    PdfObject? toUni = await fontDictionary.get(PdfName.toUnicode);
    if (toUni is PdfStream) {
      toUnicode = await CPDF_ToUnicodeMap.load(toUni);
    }

    if (toUnicode == null) {
      PdfArray? descendantFonts =
          await fontDictionary.getAsArray(PdfName.descendantFonts);
      if (descendantFonts != null && descendantFonts.size() > 0) {
        PdfDictionary? cidFont = await descendantFonts.getAsDictionary(0);
        if (cidFont != null) {
          PdfDictionary? cidSystemInfo =
              await cidFont.getAsDictionary(PdfName.cidSystemInfo);
          if (cidSystemInfo != null) {
            String? registry =
                (await cidSystemInfo.getAsString(PdfName("Registry")))
                    ?.getValue();
            String? ordering =
                (await cidSystemInfo.getAsString(PdfName("Ordering")))
                    ?.getValue();
            if (registry != null && ordering != null) {
              cid2unicode = await CPDF_FontGlobals()
                  .getCID2UnicodeMap(registry, ordering);
            }
          }
        }
      }
    }
  }

  @override
  Glyph? getGlyph(int unicode) {
    return getFontProgram()?.getGlyph(unicode);
  }

  @override
  bool containsGlyph(int unicode) {
    return getFontProgram()?.getGlyph(unicode) != null;
  }

  @override
  void writeText(dynamic text, dynamic stream, [int? from, int? to]) {
    if (text is GlyphLine && stream is PdfOutputStream) {
      int start = from ?? text.getStart();
      int end = to ?? text.getEnd();
      if (end > start) {
        Uint8List bytes = convertToBytes(GlyphLine.copySlice(text, start, end));
        _writeHexedString(stream, bytes);
      }
    } else if (text is String && stream is PdfOutputStream) {
      writeTextString(text, stream);
    }
  }

  void writeTextString(String text, PdfOutputStream stream) {
    _writeHexedString(stream, convertToBytes(text));
  }

  @override
  Uint8List convertToBytes(dynamic text) {
    if (text is String) {
      BytesBuilder builder = BytesBuilder();
      for (int i = 0; i < text.length; i++) {
        int charCode;
        if (TextUtil.isSurrogatePair(text, i)) {
          charCode = TextUtil.convertToUtf32(text, i);
          i++;
        } else {
          charCode = text.codeUnitAt(i);
        }
        Glyph? g = getGlyph(charCode);
        if (g != null) {
          utilizedGlyphs[g.getCode()] = g;
          builder.add(cmapEncoding.getCmapBytes(g.getCode()));
        } else {
          builder.add([0, 0]);
        }
      }
      return builder.toBytes();
    } else if (text is GlyphLine) {
      BytesBuilder builder = BytesBuilder();
      for (int i = text.getStart(); i < text.getEnd(); i++) {
        Glyph g = text.get(i);
        utilizedGlyphs[g.getCode()] = g;
        builder.add(cmapEncoding.getCmapBytes(g.getCode()));
      }
      return builder.toBytes();
    }
    return PdfFont.EMPTY_BYTES;
  }

  void _writeHexedString(PdfOutputStream stream, Uint8List bytes) {
    stream.writeByte(60); // <
    for (int b in bytes) {
      String hex = b.toRadixString(16).padLeft(2, '0').toUpperCase();
      stream.writeString(hex);
    }
    stream.writeByte(62); // >
  }

  @override
  Future<void> flush() async {
    if (isFlushed()) return;
    ensureUnderlyingObjectHasIndirectReference();
    if (newFont) {
      flushFontData();
    }
    await super.flush();
  }

  void flushFontData() {
    PdfDictionary fontDict = getPdfObject();
    fontDict.put(PdfName.type, PdfName.font);
    fontDict.put(PdfName.subtype, PdfName.type0);

    String baseFontName = getFontProgram()!.getFontNames().getFontName()!;
    fontDict.put(
        PdfName.baseFont, PdfName("$baseFontName-${cmapEncoding.cmap}"));
    fontDict.put(PdfName.encoding, PdfName(cmapEncoding.cmap));

    PdfDictionary fontDescriptor = getFontDescriptor(baseFontName);
    PdfDictionary cidFont = getCidFont(fontDescriptor, baseFontName);

    fontDict.put(PdfName.descendantFonts, PdfArray()..add(cidFont));

    PdfStream? toUnicode = getToUnicode();
    if (toUnicode != null) {
      fontDict.put(PdfName.toUnicode, toUnicode);
    }
  }

  PdfDictionary getCidFont(PdfDictionary fontDescriptor, String fontName) {
    PdfDictionary cidFont = PdfDictionary();
    cidFont.put(PdfName.type, PdfName.font);
    cidFont.put(PdfName.subtype, PdfName.cidFontType2);
    cidFont.put(PdfName.baseFont, PdfName(fontName));
    cidFont.put(PdfName.fontDescriptor, fontDescriptor);
    cidFont.put(PdfName.cidToGIDMap, PdfName.identity);

    PdfDictionary cidInfo = PdfDictionary();
    cidInfo.put(
        PdfName.intern("Registry"), PdfString(cmapEncoding.getRegistry()));
    cidInfo.put(
        PdfName.intern("Ordering"), PdfString(cmapEncoding.getOrdering()));
    cidInfo.put(PdfName.intern("Supplement"),
        PdfNumber(cmapEncoding.getSupplement().toDouble()));
    cidFont.put(PdfName.cidSystemInfo, cidInfo);

    if (!vertical) {
      cidFont.put(PdfName.dw, PdfNumber(1000)); // Default width
      PdfArray? widthsArray = generateWidthsArray();
      if (widthsArray != null) {
        cidFont.put(PdfName.w, widthsArray);
      }
    }

    return cidFont;
  }

  PdfArray? generateWidthsArray() {
    if (utilizedGlyphs.isEmpty) return null;

    // Simple implementation for now: [cid [w1 w2 ...]]
    //  uses more optimized format, but let's start with this.
    List<int> sortedCids = utilizedGlyphs.keys.toList()..sort();

    PdfArray res = PdfArray();
    if (sortedCids.isEmpty) return null;

    int lastCid = -10;
    PdfArray? currentGroup;

    for (int cid in sortedCids) {
      Glyph? g = utilizedGlyphs[cid];
      if (g == null || g.getWidth() == 1000) continue;

      if (cid == lastCid + 1 && currentGroup != null) {
        currentGroup.add(PdfNumber(g.getWidth().toDouble()));
      } else {
        currentGroup = PdfArray();
        currentGroup.add(PdfNumber(g.getWidth().toDouble()));
        res.add(PdfNumber(cid.toDouble()));
        res.add(currentGroup);
      }
      lastCid = cid;
    }

    return res.size() == 0 ? null : res;
  }

  PdfStream? getToUnicode() {
    List<Glyph> toUnicodeGlyphs = [];
    for (var entry in utilizedGlyphs.entries) {
      if (entry.key > 0) {
        toUnicodeGlyphs.add(entry.value);
      }
    }
    if (toUnicodeGlyphs.isEmpty) return null;
    return FontUtil.getToUnicodeStream(toUnicodeGlyphs);
  }

  @override
  PdfDictionary getFontDescriptor(String fontName) {
    PdfDictionary fd = PdfDictionary();
    fd.put(PdfName.type, PdfName.fontDescriptor);
    fd.put(PdfName.fontName, PdfName(fontName));

    final metrics = getFontProgram()!.getFontMetrics();
    fd.put(
        PdfName.fontBBox,
        PdfArray.fromDoubles(
            metrics.getBbox().map((e) => e.toDouble()).toList()));
    fd.put(PdfName.ascent, PdfNumber(metrics.getTypoAscender().toDouble()));
    fd.put(PdfName.descent, PdfNumber(metrics.getTypoDescender().toDouble()));
    fd.put(PdfName.capHeight, PdfNumber(metrics.getCapHeight().toDouble()));
    fd.put(PdfName.italicAngle, PdfNumber(metrics.getItalicAngle()));
    fd.put(PdfName.stemV, PdfNumber(80));
    fd.put(PdfName.flags,
        PdfNumber(getFontProgram()!.getPdfFontFlags().toDouble()));

    addFontStream(fd);

    return fd;
  }

  void addFontStream(PdfDictionary fd) {
    if (embedded) {
      TrueTypeFont ttf = getFontProgram() as TrueTypeFont;
      Uint8List? fontBytes;
      PdfName fontFileKey;

      if (ttf.isCff()) {
        fontBytes = ttf.readCffFont();
        fontFileKey = PdfName.fontFile3;
      } else {
        fontBytes = ttf.getFontStreamBytes();
        fontFileKey = PdfName.fontFile2;
      }

      if (fontBytes != null) {
        PdfStream stream = PdfStream.withBytes(fontBytes);
        if (ttf.isCff()) {
          stream.put(PdfName.subtype, PdfName("Type1C"));
        }
        fd.put(fontFileKey, stream);
      }
    }
  }

  @override
  GlyphLine createGlyphLine(String content) {
    List<Glyph> glyphs = [];
    for (int i = 0; i < content.length; i++) {
      glyphs.add(getGlyph(content.codeUnitAt(i)) ?? Glyph(-1, 0, 0));
    }
    return GlyphLine(glyphs);
  }

  @override
  int appendGlyphs(String text, int from, int to, List<Glyph> glyphs) {
    int processed = 0;
    for (int i = from; i <= to; i++) {
      Glyph? g = getGlyph(text.codeUnitAt(i));
      if (g != null) {
        glyphs.add(g);
        processed++;
      } else
        break;
    }
    return processed;
  }

  @override
  int appendAnyGlyph(String text, int from, List<Glyph> glyphs) {
    Glyph? g = getGlyph(text.codeUnitAt(from));
    if (g != null) {
      glyphs.add(g);
      return 1;
    }
    return 0;
  }

  @override
  String decode(PdfString content) {
    if (toUnicode != null || cid2unicode != null) {
      Uint8List? bytes = content.getValueBytes();
      if (bytes == null) return "";
      StringBuffer sb = StringBuffer();
      int i = 0;
      while (i < bytes.length) {
        int code = cmapEncoding.getCidCodeFromBytes(bytes, i);
        int len = cmapEncoding.getCidCodeLengthFromBytes(bytes, i);
        i += len;
        if (toUnicode != null) {
          sb.write(toUnicode!.lookup(code));
        } else {
          int uni = cid2unicode!.unicodeFromCID(code);
          if (uni != 0) {
            sb.writeCharCode(uni);
          }
        }
      }
      return sb.toString();
    }
    return decodeIntoGlyphLine(content).toString();
  }

  @override
  GlyphLine decodeIntoGlyphLine(PdfString content) {
    List<Glyph> glyphs = [];
    Uint8List? bytes = content.getValueBytes();
    if (bytes == null) return GlyphLine([]);
    int i = 0;
    while (i < bytes.length) {
      int code = cmapEncoding.getCidCodeFromBytes(bytes, i);
      int len = cmapEncoding.getCidCodeLengthFromBytes(bytes, i);
      i += len;
      glyphs.add(getFontProgram()?.getGlyphByCode(code) ?? Glyph(code, 0, 0));
    }
    return GlyphLine(glyphs);
  }

  @override
  double getContentWidth(PdfString content) {
    double total = 0;
    GlyphLine line = decodeIntoGlyphLine(content);
    for (int i = line.getStart(); i < line.getEnd(); i++) {
      total += line.get(i).getWidth();
    }
    return total;
  }
}
