import 'dart:typed_data';
import '../../platform/io.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'package:dpdf/src/io/font/font_names.dart';
import 'package:dpdf/src/commons/utils/tuple2.dart';
import 'package:dpdf/src/io/font/true_type_font_subsetter.dart';

class HeaderTable {
  int flags = 0;
  int unitsPerEm = 0;
  int xMin = 0;
  int yMin = 0;
  int xMax = 0;
  int yMax = 0;
  int macStyle = 0;
}

class HorizontalHeader {
  int Ascender = 0;
  int Descender = 0;
  int LineGap = 0;
  int advanceWidthMax = 0;
  int minLeftSideBearing = 0;
  int minRightSideBearing = 0;
  int xMaxExtent = 0;
  int caretSlopeRise = 0;
  int caretSlopeRun = 0;
  int numberOfHMetrics = 0;
}

class WindowsMetrics {
  int xAvgCharWidth = 0;
  int usWeightClass = 0;
  int usWidthClass = 0;
  int fsType = 0;
  int ySubscriptXSize = 0;
  int ySubscriptYSize = 0;
  int ySubscriptXOffset = 0;
  int ySubscriptYOffset = 0;
  int ySuperscriptXSize = 0;
  int ySuperscriptYSize = 0;
  int ySuperscriptXOffset = 0;
  int ySuperscriptYOffset = 0;
  int yStrikeoutSize = 0;
  int yStrikeoutPosition = 0;
  int sFamilyClass = 0;
  Uint8List panose = Uint8List(10);
  Uint8List achVendID = Uint8List(4);
  int fsSelection = 0;
  int usFirstCharIndex = 0;
  int usLastCharIndex = 0;
  int sTypoAscender = 0;
  int sTypoDescender = 0;
  int sTypoLineGap = 0;
  int usWinAscent = 0;
  int usWinDescent = 0;
  int ulCodePageRange1 = 0;
  int ulCodePageRange2 = 0;
  int sxHeight = 0;
  int sCapHeight = 0;
}

class PostTable {
  double italicAngle = 0;
  int underlinePosition = 0;
  int underlineThickness = 0;
  bool isFixedPitch = false;
}

class CmapTable {
  List<Tuple2<int, int>> cmapEncodings = []; // [platformID, encodingID]
  Map<int, List<int>>? cmap03;
  Map<int, List<int>>? cmap10;
  Map<int, List<int>>? cmap30;
  Map<int, List<int>>? cmap31;
  Map<int, List<int>>? cmap310;
  bool fontSpecific = false;
}

class CraftOpenTypeParser {
  late CraftRandomAccessFileOrArray raf;
  String? fileName;
  int ttcIndex = -1;
  int directoryOffset = 0;
  String? fontName;
  Map<int, List<List<String>>> allNameEntries = {};
  bool cff = false;
  int cffOffset = 0;
  int cffLength = 0;
  bool isLenientMode = false;

  late HeaderTable head;
  late HorizontalHeader hhea;
  late WindowsMetrics os_2;
  late PostTable post;
  late CmapTable cmaps;
  List<int> glyphWidthsByIndex = [];
  List<int> locaTable = [];

  static const int ARG_1_AND_2_ARE_WORDS = 1;
  static const int WE_HAVE_A_SCALE = 8;
  static const int MORE_COMPONENTS = 32;
  static const int WE_HAVE_AN_X_AND_Y_SCALE = 64;
  static const int WE_HAVE_A_TWO_BY_TWO = 128;

  Map<String, List<int>> tables = {};

  CraftOpenTypeParser(Uint8List ttf, [this.isLenientMode = false]) {
    raf = CraftRandomAccessFileOrArray(ttf);
    initializeSfntTables();
  }

  CraftOpenTypeParser.fromFile(String filename, [this.isLenientMode = false]) {
    fileName = filename;
    raf = CraftRandomAccessFileOrArray.fromFile(File(filename));
    initializeSfntTables();
  }

  int getDirectoryOffset() => directoryOffset;

  void initializeSfntTables() {
    tables = {};
    raf.seek(directoryOffset);
    int ttId = raf.readInt();
    if (ttId != 0x00010000 && ttId != 0x4F54544F && ttId != 0x74746366) {
      // 0x74746366 is 'ttcf'
      // throw Exception("Not a valid TTF/OTF file");
    }

    int num_tables = raf.readUnsignedShort();
    raf.skipBytes(6); // searchRange, entrySelector, rangeShift

    for (int k = 0; k < num_tables; ++k) {
      String tag = readStandardString(4);
      raf.readInt(); // checksum
      int offset = raf.readInt();
      int length = raf.readInt();
      tables[tag] = [offset, length];
    }
  }

  String readStandardString(int length) {
    StringBuffer sb = StringBuffer();
    for (int k = 0; k < length; ++k) {
      sb.writeCharCode(raf.readUnsignedByte());
    }
    return sb.toString();
  }

  void loadTables(bool all) {
    readHeadTable();
    readHheaTable();
    loadWindowsMetrics();
    readPostTable();
    readNameTable();
    if (all) {
      checkCff();
      readGlyphWidths();
      readCmapTable();
      readLoca();
    }

    if (all) {
      // Tables are read or accessed on demand. Key tables for metrics are pre-loaded.
      // Other tables like 'kern' or 'glyf' are loaded when needed.
    }
  }

  // Placeholder methods for table reading
  void readHeadTable() {
    List<int>? tableLocation = tables["head"];
    if (tableLocation == null)
      throw Exception("Table 'head' does not exist in $fileName");
    raf.seek(tableLocation[0] + 16);
    head = HeaderTable();
    head.flags = raf.readUnsignedShort();
    head.unitsPerEm = raf.readUnsignedShort();
    raf.skipBytes(16);
    head.xMin = raf.readShort();
    head.yMin = raf.readShort();
    head.xMax = raf.readShort();
    head.yMax = raf.readShort();
    head.macStyle = raf.readUnsignedShort();
  }

  void readHheaTable() {
    List<int>? tableLocation = tables["hhea"];
    if (tableLocation == null)
      throw Exception("Table 'hhea' does not exist in $fileName");
    raf.seek(tableLocation[0] + 4);
    hhea = HorizontalHeader();
    hhea.Ascender = raf.readShort();
    hhea.Descender = raf.readShort();
    hhea.LineGap = raf.readShort();
    hhea.advanceWidthMax = raf.readUnsignedShort();
    hhea.minLeftSideBearing = raf.readShort();
    hhea.minRightSideBearing = raf.readShort();
    hhea.xMaxExtent = raf.readShort();
    hhea.caretSlopeRise = raf.readShort();
    hhea.caretSlopeRun = raf.readShort();
    raf.skipBytes(12);
    hhea.numberOfHMetrics = raf.readUnsignedShort();
  }

  /// Reads only the declared OS/2 table span, using the versioned field offsets
  /// from the OpenType format. No field read can enter the following table.
  void loadWindowsMetrics() {
    final span = tables['OS/2'];
    if (span == null) {
      os_2 = WindowsMetrics();
      return;
    }
    if (span.length != 2 ||
        span[0] < 0 ||
        span[1] < 2 ||
        span[0] > raf.length() - span[1]) {
      throw FormatException('OS/2 table span is outside the font data.');
    }
    final raw =
        Uint8List.sublistView(raf.getBytes(), span[0], span[0] + span[1]);
    final fields = ByteData.sublistView(raw);
    final revision = fields.getUint16(0);
    if (revision > 5)
      throw UnsupportedError('OS/2 revision $revision is unsupported.');
    final required = switch (revision) {
      0 => span[1] == 68 ? 68 : 78,
      1 => 86,
      5 => 100,
      _ => 96,
    };
    if (raw.length < required) {
      throw FormatException(
          'OS/2 revision $revision requires $required bytes.');
    }
    final value = WindowsMetrics();
    // Fields are grouped by meaning rather than by sequential cursor movement.
    value.panose = Uint8List.fromList(raw.sublist(32, 42));
    value.achVendID = Uint8List.fromList(raw.sublist(58, 62));
    value.fsSelection = fields.getUint16(62);
    value.fsType = fields.getUint16(8);
    value.sFamilyClass = fields.getInt16(30);
    value.usWeightClass = fields.getUint16(4);
    value.usWidthClass = fields.getUint16(6);
    value.xAvgCharWidth = fields.getInt16(2);
    value.usFirstCharIndex = fields.getUint16(64);
    value.usLastCharIndex = fields.getUint16(66);

    final smallForms = <void Function(int)>[
      (n) => value.ySubscriptXSize = n,
      (n) => value.ySubscriptYSize = n,
      (n) => value.ySubscriptXOffset = n,
      (n) => value.ySubscriptYOffset = n,
      (n) => value.ySuperscriptXSize = n,
      (n) => value.ySuperscriptYSize = n,
      (n) => value.ySuperscriptXOffset = n,
      (n) => value.ySuperscriptYOffset = n,
    ];
    for (var field = 0; field < smallForms.length; field++) {
      smallForms[field](fields.getInt16(10 + field * 2));
    }
    value.yStrikeoutPosition = fields.getInt16(28);
    value.yStrikeoutSize = fields.getInt16(26);

    if (raw.length >= 78) {
      value.usWinDescent = fields.getUint16(76);
      value.usWinAscent = fields.getUint16(74);
      value.sTypoLineGap = fields.getInt16(72);
      value.sTypoDescender = -fields.getInt16(70).abs();
      value.sTypoAscender = fields.getInt16(68);
    }
    if (revision >= 1) {
      value.ulCodePageRange2 = fields.getUint32(82);
      value.ulCodePageRange1 = fields.getUint32(78);
    }
    if (revision >= 2) {
      value.sCapHeight = fields.getInt16(88);
      value.sxHeight = fields.getInt16(86);
    }
    os_2 = value;
  }

  void readPostTable() {
    List<int>? tableLocation = tables["post"];
    post = PostTable();
    if (tableLocation != null) {
      raf.seek(tableLocation[0] + 4);
      int mantissa = raf.readShort();
      int fraction = raf.readUnsignedShort();
      post.italicAngle = mantissa + fraction / 16384.0;
      post.underlinePosition = raf.readShort();
      post.underlineThickness = raf.readShort();
      post.isFixedPitch = raf.readInt() != 0;
    }
  }

  void readNameTable() {
    List<int>? tableLocation = tables["name"];
    if (tableLocation != null) {
      raf.seek(tableLocation[0] + 2);
      int numRecords = raf.readUnsignedShort();
      int startOfStorage = raf.readUnsignedShort();
      for (int k = 0; k < numRecords; ++k) {
        int platformID = raf.readUnsignedShort();
        int platformEncodingID = raf.readUnsignedShort();
        int languageID = raf.readUnsignedShort();
        int nameID = raf.readUnsignedShort();
        int length = raf.readUnsignedShort();
        int offset = raf.readUnsignedShort();

        if (allNameEntries[nameID] == null) {
          allNameEntries[nameID] = [];
        }
        String name;
        int pos = raf.getPosition();
        try {
          raf.seek(tableLocation[0] + startOfStorage + offset);
          if (platformID == 0 || platformID == 3) {
            name = raf.readString(length, "UTF-16BE");
          } else {
            name = raf.readString(length, "ISO-8859-1");
          }
        } finally {
          raf.seek(pos);
        }
        allNameEntries[nameID]!.add([
          platformID.toString(),
          platformEncodingID.toString(),
          languageID.toString(),
          name
        ]);
      }
    }
  }

  void checkCff() {
    if (tables["CFF "] != null) {
      cff = true;
      cffOffset = tables["CFF "]![0];
      cffLength = tables["CFF "]![1];
    }
  }

  void readGlyphWidths() {
    List<int>? tableLocation = tables["hmtx"];
    if (tableLocation == null) {
      throw Exception("Table 'hmtx' does not exist in $fileName");
    }

    glyphWidthsByIndex = List.filled(readNumGlyphs(), 0);
    raf.seek(tableLocation[0]);
    int numberOfHMetrics = hhea.numberOfHMetrics;
    int unitsPerEm = head.unitsPerEm;

    for (int k = 0; k < numberOfHMetrics; ++k) {
      int w = raf.readUnsignedShort();
      glyphWidthsByIndex[k] = (w * 1000) ~/ unitsPerEm;
      raf.readShort(); // leftSideBearing
    }

    if (numberOfHMetrics > 0) {
      int lastWidth = glyphWidthsByIndex[numberOfHMetrics - 1];
      for (int k = numberOfHMetrics; k < glyphWidthsByIndex.length; k++) {
        glyphWidthsByIndex[k] = lastWidth;
      }
    }
  }

  void readLoca() {
    List<int>? tableLocation = tables["loca"];
    if (tableLocation == null) return;
    raf.seek(tables["head"]![0] + 50); // indexToLocFormat offset
    bool locaShortTable = raf.readUnsignedShort() == 0;

    raf.seek(tableLocation[0]);
    if (locaShortTable) {
      int entries = tableLocation[1] ~/ 2;
      locaTable = List.filled(entries, 0);
      for (int k = 0; k < entries; ++k) {
        locaTable[k] = raf.readUnsignedShort() * 2;
      }
    } else {
      int entries = tableLocation[1] ~/ 4;
      locaTable = List.filled(entries, 0);
      for (int k = 0; k < entries; ++k) {
        locaTable[k] = raf.readInt();
      }
    }
  }

  void readCmapTable() {
    List<int>? tableLocation = tables["cmap"];
    if (tableLocation == null) {
      throw Exception("Table 'cmap' does not exist in $fileName");
    }
    raf.seek(tableLocation[0]);
    raf.skipBytes(2);
    int num_tables = raf.readUnsignedShort();
    int map03 = 0, map10 = 0, map30 = 0, map31 = 0, map310 = 0;
    cmaps = CmapTable();

    for (int k = 0; k < num_tables; ++k) {
      int platId = raf.readUnsignedShort();
      int platSpecId = raf.readUnsignedShort();
      cmaps.cmapEncodings.add(Tuple2(platId, platSpecId));
      int offset = raf.readInt();

      if (platId == 0 && platSpecId == 3)
        map03 = offset;
      else if (platId == 1 && platSpecId == 0)
        map10 = offset;
      else if (platId == 3 && platSpecId == 0) {
        cmaps.fontSpecific = true;
        map30 = offset;
      } else if (platId == 3 && platSpecId == 1)
        map31 = offset;
      else if (platId == 3 && platSpecId == 10) map310 = offset;
    }

    if (map03 > 0) {
      raf.seek(tableLocation[0] + map03);
      int format = raf.readUnsignedShort();
      if (format == 4)
        cmaps.cmap03 = readFormat4(false);
      else if (format == 6) cmaps.cmap03 = readFormat6();
      cmaps.cmap31 = cmaps.cmap03;
    }
    if (map10 > 0) {
      raf.seek(tableLocation[0] + map10);
      int format = raf.readUnsignedShort();
      if (format == 0)
        cmaps.cmap10 = readFormat0();
      else if (format == 4)
        cmaps.cmap10 = readFormat4(false);
      else if (format == 6) cmaps.cmap10 = readFormat6();
    }
    if (map30 > 0) {
      raf.seek(tableLocation[0] + map30);
      int format = raf.readUnsignedShort();
      if (format == 4) {
        cmaps.cmap30 = readFormat4(cmaps.fontSpecific);
        cmaps.cmap10 = cmaps.cmap30;
      } else {
        cmaps.fontSpecific = false;
      }
    }
    if (map31 > 0) {
      raf.seek(tableLocation[0] + map31);
      int format = raf.readUnsignedShort();
      if (format == 4) cmaps.cmap31 = readFormat4(false);
    }
    if (map310 > 0) {
      // Format 12 usually
      raf.seek(tableLocation[0] + map310);
      int format = raf.readUnsignedShort();
      if (format == 12) cmaps.cmap310 = readGroupedUnicodeMap();
    }
  }

  Map<int, List<int>> readFormat0() {
    Map<int, List<int>> h = {};
    raf.skipBytes(4);
    for (int k = 0; k < 256; ++k) {
      int glyph = raf.readUnsignedByte();
      h[k] = [glyph, getGlyphWidth(glyph)];
    }
    return h;
  }

  Map<int, List<int>> readFormat4(bool fontSpecific) {
    Map<int, List<int>> h = {};
    raf.readUnsignedShort();
    raf.skipBytes(2);
    int segCount = raf.readUnsignedShort() ~/ 2;
    raf.skipBytes(6);
    List<int> endCount = List.filled(segCount, 0);
    for (int k = 0; k < segCount; k++) endCount[k] = raf.readUnsignedShort();
    raf.skipBytes(2);
    List<int> startCount = List.filled(segCount, 0);
    for (int k = 0; k < segCount; k++) startCount[k] = raf.readUnsignedShort();
    List<int> idDelta = List.filled(segCount, 0);
    for (int k = 0; k < segCount; k++) idDelta[k] = raf.readUnsignedShort();
    List<int> idRO = List.filled(segCount, 0);

    int currentPos = raf.getPosition();
    for (int k = 0; k < segCount; k++) {
      idRO[k] = raf.readUnsignedShort();
    }

    for (int k = 0; k < segCount; k++) {
      int glyph;
      for (int j = startCount[k]; j <= endCount[k] && j != 0xFFFF; j++) {
        if (idRO[k] == 0) {
          glyph = (j + idDelta[k]) & 0xFFFF;
        } else {
          // The offset is relative to the position of idRO[k] reader
          // idRO[k] is at currentPos + k*2
          int idRoOffset = currentPos + k * 2;
          int glyphOffset = idRoOffset + idRO[k] + (j - startCount[k]) * 2;
          int savePos = raf.getPosition();
          raf.seek(glyphOffset);
          glyph = raf.readUnsignedShort();
          if (glyph != 0) glyph = (glyph + idDelta[k]) & 0xFFFF;
          raf.seek(savePos);
        }
        if (fontSpecific && (j & 0xFF00) == 0xF000) {
          h[j & 0xFF] = [glyph, getGlyphWidth(glyph)];
        } else {
          h[j] = [glyph, getGlyphWidth(glyph)];
        }
      }
    }
    return h;
  }

  Map<int, List<int>> readFormat6() {
    Map<int, List<int>> h = {};
    raf.skipBytes(4);
    int firstCode = raf.readUnsignedShort();
    int entryCount = raf.readUnsignedShort();
    for (int k = 0; k < entryCount; k++) {
      int glyph = raf.readUnsignedShort();
      h[k + firstCode] = [glyph, getGlyphWidth(glyph)];
    }
    return h;
  }

  Map<int, List<int>> readGroupedUnicodeMap() {
    final start = raf.getPosition() - 2;
    final parent = tables['cmap'];
    final limit = parent == null ? raf.length() : parent[0] + parent[1];
    if (start < 0 || start > limit - 16 || limit > raf.length()) {
      throw FormatException('Grouped cmap header is outside its table.');
    }
    final header = ByteData.sublistView(raf.getBytes(), start, start + 16);
    final size = header.getUint32(4);
    final count = header.getUint32(12);
    if (header.getUint16(0) != 12 ||
        header.getUint16(2) != 0 ||
        size < 16 ||
        size > limit - start ||
        count > (size - 16) ~/ 12) {
      throw FormatException('Grouped cmap has invalid header or group count.');
    }
    final records =
        ByteData.sublistView(raf.getBytes(), start + 16, start + size);
    final intervals = <(int, int, int)>[];
    var previousEnd = -1;
    for (var record = 0; record < count * 12; record += 12) {
      final lower = records.getUint32(record);
      final upper = records.getUint32(record + 4);
      final firstGlyph = records.getUint32(record + 8);
      if (lower <= previousEnd ||
          upper < lower ||
          upper > 0x10ffff ||
          (lower <= 0xdfff && upper >= 0xd800) ||
          firstGlyph + upper - lower >= glyphWidthsByIndex.length) {
        throw FormatException(
            'Grouped cmap has invalid Unicode or glyph interval.');
      }
      intervals.add((lower, upper - lower + 1, firstGlyph));
      previousEnd = upper;
    }
    final result = <int, List<int>>{};
    for (final (unicode, length, glyph) in intervals) {
      for (var relative = 0; relative < length; relative++) {
        final index = glyph + relative;
        result[unicode + relative] = [index, glyphWidthsByIndex[index]];
      }
    }
    raf.seek(start + size);
    return result;
  }

  int getGlyphWidth(int glyph) {
    if (glyph >= glyphWidthsByIndex.length)
      glyph = glyphWidthsByIndex.length - 1;
    return glyphWidthsByIndex[glyph];
  }

  Map<int, int> readKerning(int unitsPerEm) {
    Map<int, int> kerning = {};
    List<int>? tableLocation = tables["kern"];
    if (tableLocation == null) return kerning;

    raf.seek(tableLocation[0] + 2);
    int nTables = raf.readUnsignedShort();
    int checkpoint = tableLocation[0] + 4;
    int length = 0;

    for (int k = 0; k < nTables; k++) {
      checkpoint += length;
      raf.seek(checkpoint);
      raf.skipBytes(2);
      length = raf.readUnsignedShort();
      int coverage = raf.readUnsignedShort();
      if ((coverage & 0xfff7) == 0x0001) {
        // Format 0
        int nPairs = raf.readUnsignedShort();
        raf.skipBytes(6);
        for (int j = 0; j < nPairs; j++) {
          int pair = raf.readInt();
          int value = (raf.readShort() * 1000) ~/ unitsPerEm;
          kerning[pair] = value;
        }
      }
    }
    return kerning;
  }

  List<List<int>>? readBbox(int unitsPerEm) {
    if (locaTable.isEmpty) return null;
    List<int>? tableLocation = tables["glyf"];
    if (tableLocation == null) throw Exception("glyf table not found");

    int tableGlyphOffset = tableLocation[0];
    List<List<int>> bboxes = List.generate(locaTable.length - 1, (index) => []);

    for (int glyph = 0; glyph < locaTable.length - 1; ++glyph) {
      int start = locaTable[glyph];
      if (start != locaTable[glyph + 1]) {
        raf.seek(tableGlyphOffset + start + 2);
        bboxes[glyph] = [
          (raf.readShort() * 1000) ~/ unitsPerEm,
          (raf.readShort() * 1000) ~/ unitsPerEm,
          (raf.readShort() * 1000) ~/ unitsPerEm,
          (raf.readShort() * 1000) ~/ unitsPerEm
        ];
      }
    }
    return bboxes;
  }

  Uint8List getFullFont() {
    // Return copy of inner data
    // For now we assume we read everything or can seek back
    // Since RandomAccessFileOrArray abstracts a file or array, we can use it.
    // But RandomAccessFileOrArray doesn't easily expose "all bytes".
    // If initialized from bytes, we have them.
    // If from file, we need to read them.

    // Optimized full access using getBytes()
    return Uint8List.fromList(raf.getBytes());
  }

  CraftFontNames getFontNames() {
    CraftFontNames fn = CraftFontNames();
    fn.setAllNames(allNameEntries);
    if (allNameEntries[6] != null && allNameEntries[6]!.isNotEmpty) {
      fn.setFontName(allNameEntries[6]![0][3]);
    }
    // Check embedding license: fsType 2 means restricted
    fn.setAllowEmbedding((os_2.fsType & 0x0002) == 0);
    fn.setMacStyle(head.macStyle);
    fn.setFontWeight(os_2.usWeightClass);
    return fn;
  }

  Tuple2<int, Uint8List> getSubset(Iterable<int> glyphs, bool subsetTables) {
    TrueTypeFontSubsetter sb =
        TrueTypeFontSubsetter(fileName ?? "", this, glyphs, subsetTables);
    return sb.process();
  }

  int readNumGlyphs() {
    List<int>? maxp = tables["maxp"];
    if (maxp == null) return 65536;
    raf.seek(maxp[0] + 4);
    return raf.readUnsignedShort();
  }

  List<int> getFlatGlyphs(Iterable<int> glyphs) {
    Set<int> glyphsUsed = Set<int>.from(glyphs);
    List<int> glyphsInList = List<int>.from(glyphs);
    const int glyph0 = 0;
    if (!glyphsUsed.contains(glyph0)) {
      glyphsUsed.add(glyph0);
      glyphsInList.add(glyph0);
    }
    List<int>? tableLocation = tables["glyf"];
    if (tableLocation == null) {
      throw Exception("Table 'glyf' does not exist in $fileName");
    }
    int glyfOffset = tableLocation[0];
    for (int i = 0; i < glyphsInList.length; i++) {
      _checkGlyphComposite(
          glyphsInList[i], glyphsUsed, glyphsInList, glyfOffset);
    }
    return glyphsInList;
  }

  void _checkGlyphComposite(
      int glyph, Set<int> glyphsUsed, List<int> glyphsInList, int glyfOffset) {
    int start = locaTable[glyph];
    if (start == locaTable[glyph + 1]) {
      return;
    }
    CraftRandomAccessFileOrArray tmpRaf = raf.createView();
    try {
      tmpRaf.seek(glyfOffset + start);
      int numContours = tmpRaf.readShort();
      if (numContours >= 0) {
        return;
      }
      tmpRaf.skipBytes(8);
      while (true) {
        int flags = tmpRaf.readUnsignedShort();
        int cGlyph = tmpRaf.readUnsignedShort();
        if (!glyphsUsed.contains(cGlyph)) {
          glyphsUsed.add(cGlyph);
          glyphsInList.add(cGlyph);
        }
        if ((flags & MORE_COMPONENTS) == 0) {
          return;
        }
        int skip;
        if ((flags & ARG_1_AND_2_ARE_WORDS) != 0) {
          skip = 4;
        } else {
          skip = 2;
        }
        if ((flags & WE_HAVE_A_SCALE) != 0) {
          skip += 2;
        } else if ((flags & WE_HAVE_AN_X_AND_Y_SCALE) != 0) {
          skip += 4;
        } else if ((flags & WE_HAVE_A_TWO_BY_TWO) != 0) {
          skip += 8;
        }
        tmpRaf.skipBytes(skip);
      }
    } finally {
      tmpRaf.close();
    }
  }

  Uint8List getGlyphDataForGid(int gid) {
    List<int>? tableLocation = tables["glyf"];
    if (tableLocation == null) {
      throw Exception("Table 'glyf' does not exist in $fileName");
    }
    int glyfOffset = tableLocation[0];
    int start = locaTable[gid];
    int len = locaTable[gid + 1] - start;
    Uint8List data = Uint8List(len);
    CraftRandomAccessFileOrArray tmpRaf = raf.createView();
    try {
      tmpRaf.seek(glyfOffset + start);
      tmpRaf.readFully(data);
      return data;
    } finally {
      tmpRaf.close();
    }
  }

  Uint8List getHorizontalMetricForGid(int gid) {
    List<int>? tableLocation = tables["hmtx"];
    if (tableLocation == null) {
      throw Exception("Table 'hmtx' does not exist in $fileName");
    }
    int hmtxOffset = tableLocation[0];
    CraftRandomAccessFileOrArray tmpRaf = raf.createView();
    try {
      if (gid < hhea.numberOfHMetrics) {
        tmpRaf.seek(hmtxOffset + gid * 4);
        Uint8List metric = Uint8List(4);
        tmpRaf.readFully(metric);
        return metric;
      } else {
        tmpRaf.seek(hmtxOffset +
            hhea.numberOfHMetrics * 4 +
            (gid - hhea.numberOfHMetrics) * 2);
        Uint8List metric = Uint8List(2);
        tmpRaf.readFully(metric);
        return metric;
      }
    } finally {
      tmpRaf.close();
    }
  }

  List<int> getGlyphWidthsByIndex() {
    return glyphWidthsByIndex;
  }

  Uint8List? readCffFont() {
    if (!cff) return null;
    Uint8List b = Uint8List(cffLength);
    int pos = raf.getPosition();
    raf.seek(cffOffset);
    raf.readFully(b);
    raf.seek(pos);
    return b;
  }
}
