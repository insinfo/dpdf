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
import 'unicode_code_map.dart';
import 'cid_unicode_repository.dart';
import 'cid_unicode_table.dart';

class CraftPdfType0Font extends CraftPdfFont {
  late CraftCMapEncoding cmapEncoding;
  bool vertical = false;
  Map<int, CraftGlyph> utilizedGlyphs = {};
  UnicodeCodeMap? toUnicode;
  CidUnicodeTable? cid2unicode;

  CraftPdfType0Font(CraftFontProgram fontProgram, [String cmap = "Identity-H"])
      : super() {
    this.fontProgram = fontProgram;
    embedded = true;
    vertical = cmap.endsWith("V");
    cmapEncoding = CraftCMapEncoding(cmap);
  }

  CraftPdfType0Font.fromDictionary(CraftPdfDictionary super.fontDictionary) {
    newFont = false;
  }

  @override
  Future<void> initFromDictionary(CraftPdfDictionary fontDictionary) async {
    CraftPdfObject? encoding =
        await fontDictionary.get(CraftPdfName.encoding, true);
    if (encoding is CraftPdfName) {
      cmapEncoding = CraftCMapEncoding(encoding.getValue());
    } else if (encoding is CraftPdfStream) {
      Uint8List? bytes = await encoding.getBytes();
      if (bytes != null) {
        cmapEncoding = CraftCMapEncoding.fromBytes("", bytes);
      } else {
        cmapEncoding = CraftCMapEncoding("Identity-H");
      }
    } else {
      cmapEncoding = CraftCMapEncoding("Identity-H");
    }

    CraftPdfObject? toUni =
        await fontDictionary.get(CraftPdfName.toUnicode, true);
    if (toUni is CraftPdfStream) {
      toUnicode = await UnicodeCodeMap.fromStream(toUni);
    }

    if (toUnicode == null) {
      CraftPdfArray? descendantFonts =
          await fontDictionary.arrayEntry(CraftPdfName.descendantFonts);
      if (descendantFonts != null && descendantFonts.size() > 0) {
        CraftPdfDictionary? cidFont = await descendantFonts.dictionaryEntry(0);
        if (cidFont != null) {
          CraftPdfDictionary? cidSystemInfo =
              await cidFont.dictionaryEntry(CraftPdfName.cidSystemInfo);
          if (cidSystemInfo != null) {
            String? registry =
                (await cidSystemInfo.stringEntry(CraftPdfName("Registry")))
                    ?.getValue();
            String? ordering =
                (await cidSystemInfo.stringEntry(CraftPdfName("Ordering")))
                    ?.getValue();
            if (registry != null && ordering != null) {
              cid2unicode = await CidUnicodeRepository.shared
                  .loadCollection(registry, ordering);
            }
          }
        }
      }
    }
  }

  @override
  CraftGlyph? getGlyph(int unicode) {
    return getFontProgram()?.getGlyph(unicode);
  }

  @override
  bool containsGlyph(int unicode) {
    return getFontProgram()?.getGlyph(unicode) != null;
  }

  @override
  void writeText(dynamic text, dynamic stream, [int? from, int? to]) {
    if (text is CraftGlyphLine && stream is CraftPdfOutputStream) {
      int start = from ?? text.getStart();
      int end = to ?? text.getEnd();
      if (end > start) {
        Uint8List bytes =
            convertToBytes(CraftGlyphLine.copySlice(text, start, end));
        _writeHexedString(stream, bytes);
      }
    } else if (text is String && stream is CraftPdfOutputStream) {
      writeTextString(text, stream);
    }
  }

  void writeTextString(String text, CraftPdfOutputStream stream) {
    _writeHexedString(stream, convertToBytes(text));
  }

  @override
  Uint8List convertToBytes(dynamic text) {
    if (text is String) {
      BytesBuilder builder = BytesBuilder();
      for (int i = 0; i < text.length; i++) {
        int charCode;
        if (CraftTextUtil.isSurrogatePair(text, i)) {
          charCode = CraftTextUtil.convertToUtf32(text, i);
          i++;
        } else {
          charCode = text.codeUnitAt(i);
        }
        CraftGlyph? g = getGlyph(charCode);
        if (g != null) {
          utilizedGlyphs[g.getCode()] = g;
          builder.add(cmapEncoding.getCmapBytes(g.getCode()));
        } else {
          builder.add([0, 0]);
        }
      }
      return builder.toBytes();
    } else if (text is CraftGlyphLine) {
      BytesBuilder builder = BytesBuilder();
      for (int i = text.getStart(); i < text.getEnd(); i++) {
        CraftGlyph g = text.get(i);
        utilizedGlyphs[g.getCode()] = g;
        builder.add(cmapEncoding.getCmapBytes(g.getCode()));
      }
      return builder.toBytes();
    }
    return CraftPdfFont.EMPTY_BYTES;
  }

  void _writeHexedString(CraftPdfOutputStream stream, Uint8List bytes) {
    stream.writeByte(60); // <
    for (int b in bytes) {
      String hex = b.toRadixString(16).padLeft(2, '0').toUpperCase();
      stream.writeString(hex);
    }
    stream.writeByte(62); // >
  }

  @override
  Future<void> flush() async {
    if (hasBeenWritten()) return;
    ensureUnderlyingObjectHasIndirectReference();
    if (newFont) {
      flushFontData();
    }
    await super.flush();
  }

  void flushFontData() {
    CraftPdfDictionary fontDict = pdfRepresentation();
    fontDict.put(CraftPdfName.type, CraftPdfName.font);
    fontDict.put(CraftPdfName.subtype, CraftPdfName.type0);

    String baseFontName = getFontProgram()!.getFontNames().getFontName()!;
    fontDict.put(CraftPdfName.baseFont,
        CraftPdfName("$baseFontName-${cmapEncoding.cmap}"));
    fontDict.put(CraftPdfName.encoding, CraftPdfName(cmapEncoding.cmap));

    CraftPdfDictionary fontDescriptor = getFontDescriptor(baseFontName);
    CraftPdfDictionary cidFont = getCidFont(fontDescriptor, baseFontName);

    fontDict.put(CraftPdfName.descendantFonts, CraftPdfArray()..add(cidFont));

    CraftPdfStream? toUnicode = getToUnicode();
    if (toUnicode != null) {
      fontDict.put(CraftPdfName.toUnicode, toUnicode);
    }
  }

  CraftPdfDictionary getCidFont(
      CraftPdfDictionary fontDescriptor, String fontName) {
    CraftPdfDictionary cidFont = CraftPdfDictionary();
    cidFont.put(CraftPdfName.type, CraftPdfName.font);
    cidFont.put(CraftPdfName.subtype, CraftPdfName.cidFontType2);
    cidFont.put(CraftPdfName.baseFont, CraftPdfName(fontName));
    cidFont.put(CraftPdfName.fontDescriptor, fontDescriptor);
    cidFont.put(CraftPdfName.cidToGIDMap, CraftPdfName.identity);

    CraftPdfDictionary cidInfo = CraftPdfDictionary();
    cidInfo.put(CraftPdfName.intern("Registry"),
        CraftPdfString(cmapEncoding.characterRegistry()));
    cidInfo.put(CraftPdfName.intern("Ordering"),
        CraftPdfString(cmapEncoding.characterCollection()));
    cidInfo.put(CraftPdfName.intern("Supplement"),
        CraftPdfNumber(cmapEncoding.collectionSupplement().toDouble()));
    cidFont.put(CraftPdfName.cidSystemInfo, cidInfo);

    if (!vertical) {
      cidFont.put(CraftPdfName.dw, CraftPdfNumber(1000)); // Default width
      CraftPdfArray? widthsArray = generateWidthsArray();
      if (widthsArray != null) {
        cidFont.put(CraftPdfName.w, widthsArray);
      }
    }

    return cidFont;
  }

  CraftPdfArray? generateWidthsArray() {
    if (utilizedGlyphs.isEmpty) return null;

    // Simple implementation for now: [cid [w1 w2 ...]]
    //  uses more optimized format, but let's start with this.
    List<int> sortedCids = utilizedGlyphs.keys.toList()..sort();

    CraftPdfArray res = CraftPdfArray();
    if (sortedCids.isEmpty) return null;

    int lastCid = -10;
    CraftPdfArray? currentGroup;

    for (int cid in sortedCids) {
      CraftGlyph? g = utilizedGlyphs[cid];
      if (g == null || g.getWidth() == 1000) continue;

      if (cid == lastCid + 1 && currentGroup != null) {
        currentGroup.add(CraftPdfNumber(g.getWidth().toDouble()));
      } else {
        currentGroup = CraftPdfArray();
        currentGroup.add(CraftPdfNumber(g.getWidth().toDouble()));
        res.add(CraftPdfNumber(cid.toDouble()));
        res.add(currentGroup);
      }
      lastCid = cid;
    }

    return res.size() == 0 ? null : res;
  }

  CraftPdfStream? getToUnicode() {
    List<CraftGlyph> toUnicodeGlyphs = [];
    for (var entry in utilizedGlyphs.entries) {
      if (entry.key > 0) {
        toUnicodeGlyphs.add(entry.value);
      }
    }
    if (toUnicodeGlyphs.isEmpty) return null;
    return CraftFontUtil.getToUnicodeStream(toUnicodeGlyphs);
  }

  @override
  CraftPdfDictionary getFontDescriptor(String fontName) {
    CraftPdfDictionary fd = CraftPdfDictionary();
    fd.put(CraftPdfName.type, CraftPdfName.fontDescriptor);
    fd.put(CraftPdfName.fontName, CraftPdfName(fontName));

    final metrics = getFontProgram()!.getFontMetrics();
    fd.put(
        CraftPdfName.fontBBox,
        CraftPdfArray.fromDoubles(
            metrics.getBbox().map((e) => e.toDouble()).toList()));
    fd.put(CraftPdfName.ascent,
        CraftPdfNumber(metrics.getTypoAscender().toDouble()));
    fd.put(CraftPdfName.descent,
        CraftPdfNumber(metrics.getTypoDescender().toDouble()));
    fd.put(CraftPdfName.capHeight,
        CraftPdfNumber(metrics.getCapHeight().toDouble()));
    fd.put(CraftPdfName.italicAngle, CraftPdfNumber(metrics.getItalicAngle()));
    fd.put(CraftPdfName.stemV, CraftPdfNumber(80));
    fd.put(CraftPdfName.flags,
        CraftPdfNumber(getFontProgram()!.getPdfFontFlags().toDouble()));

    addFontStream(fd);

    return fd;
  }

  void addFontStream(CraftPdfDictionary fd) {
    if (embedded) {
      CraftTrueTypeFont ttf = getFontProgram() as CraftTrueTypeFont;
      Uint8List? fontBytes;
      CraftPdfName fontFileKey;

      if (ttf.isCff()) {
        fontBytes = ttf.readCffFont();
        fontFileKey = CraftPdfName.fontFile3;
      } else {
        fontBytes = ttf.getFontStreamBytes();
        fontFileKey = CraftPdfName.fontFile2;
      }

      if (fontBytes != null) {
        CraftPdfStream stream = CraftPdfStream.withBytes(fontBytes);
        if (ttf.isCff()) {
          stream.put(CraftPdfName.subtype, CraftPdfName("Type1C"));
        }
        fd.put(fontFileKey, stream);
      }
    }
  }

  @override
  CraftGlyphLine createGlyphLine(String content) {
    List<CraftGlyph> glyphs = [];
    for (int i = 0; i < content.length; i++) {
      glyphs.add(getGlyph(content.codeUnitAt(i)) ?? CraftGlyph(-1, 0, 0));
    }
    return CraftGlyphLine(glyphs);
  }

  @override
  int appendGlyphs(String text, int from, int to, List<CraftGlyph> glyphs) {
    int processed = 0;
    for (int i = from; i <= to; i++) {
      CraftGlyph? g = getGlyph(text.codeUnitAt(i));
      if (g != null) {
        glyphs.add(g);
        processed++;
      } else {
        break;
      }
    }
    return processed;
  }

  @override
  int appendAnyGlyph(String text, int from, List<CraftGlyph> glyphs) {
    CraftGlyph? g = getGlyph(text.codeUnitAt(from));
    if (g != null) {
      glyphs.add(g);
      return 1;
    }
    return 0;
  }

  @override
  String decode(CraftPdfString content) {
    if (toUnicode != null || cid2unicode != null) {
      Uint8List? bytes = content.getValueBytes();
      if (bytes == null) return "";
      StringBuffer sb = StringBuffer();
      var offset = 0;
      while (offset < bytes.length) {
        final width = cmapEncoding.getCidCodeLengthFromBytes(bytes, offset);
        if (width <= 0 || offset + width > bytes.length) {
          throw FormatException(
              'Composite font text ends inside a character code.');
        }
        if (toUnicode != null) {
          // ToUnicode keys describe the original bytes, not mapped CIDs.
          var sourceCode = 0;
          for (var index = offset; index < offset + width; index++) {
            sourceCode = sourceCode * 256 + bytes[index];
          }
          sb.write(toUnicode!.textForCode(sourceCode));
        } else {
          final cid = cmapEncoding.getCidCodeFromBytes(bytes, offset);
          sb.write(cid2unicode!.textForCid(cid));
        }
        offset += width;
      }
      return sb.toString();
    }
    return decodeIntoGlyphLine(content).toString();
  }

  @override
  CraftGlyphLine decodeIntoGlyphLine(CraftPdfString content) {
    List<CraftGlyph> glyphs = [];
    Uint8List? bytes = content.getValueBytes();
    if (bytes == null) return CraftGlyphLine([]);
    int i = 0;
    while (i < bytes.length) {
      int code = cmapEncoding.getCidCodeFromBytes(bytes, i);
      int len = cmapEncoding.getCidCodeLengthFromBytes(bytes, i);
      i += len;
      glyphs.add(
          getFontProgram()?.getGlyphByCode(code) ?? CraftGlyph(code, 0, 0));
    }
    return CraftGlyphLine(glyphs);
  }

  @override
  double getContentWidth(CraftPdfString content) {
    double total = 0;
    CraftGlyphLine line = decodeIntoGlyphLine(content);
    for (int i = line.getStart(); i < line.getEnd(); i++) {
      total += line.get(i).getWidth();
    }
    return total;
  }
}
