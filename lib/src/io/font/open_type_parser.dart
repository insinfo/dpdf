import 'dart:typed_data';
import 'dart:io';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'package:dpdf/src/io/font/font_names.dart';

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

class Tuple2<T1, T2> {
  final T1 item1;
  final T2 item2;
  Tuple2(this.item1, this.item2);
}

class OpenTypeParser {
  late RandomAccessFileOrArray raf;
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

  Map<String, List<int>> tables = {};

  OpenTypeParser(Uint8List ttf, [this.isLenientMode = false]) {
    raf = RandomAccessFileOrArray(ttf);
    initializeSfntTables();
  }

  OpenTypeParser.fromFile(String filename, [this.isLenientMode = false]) {
    fileName = filename;
    raf = RandomAccessFileOrArray.fromFile(File(filename));
    initializeSfntTables();
  }

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
    readOs2Table();
    readPostTable();
    readNameTable();
    if (all) {
      checkCff();
      readGlyphWidths();
      readCmapTable();
      readLoca();
    }

    if (all) {
      // TODO: Read other tables if necessary
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

  void readOs2Table() {
    List<int>? tableLocation = tables["OS/2"];
    os_2 = WindowsMetrics();
    if (tableLocation != null) {
      raf.seek(tableLocation[0]);
      int version = raf.readUnsignedShort();
      os_2.xAvgCharWidth = raf.readShort();
      os_2.usWeightClass = raf.readUnsignedShort();
      os_2.usWidthClass = raf.readUnsignedShort();
      os_2.fsType = raf.readShort();
      os_2.ySubscriptXSize = raf.readShort();
      os_2.ySubscriptYSize = raf.readShort();
      os_2.ySubscriptXOffset = raf.readShort();
      os_2.ySubscriptYOffset = raf.readShort();
      os_2.ySuperscriptXSize = raf.readShort();
      os_2.ySuperscriptYSize = raf.readShort();
      os_2.ySuperscriptXOffset = raf.readShort();
      os_2.ySuperscriptYOffset = raf.readShort();
      os_2.yStrikeoutSize = raf.readShort();
      os_2.yStrikeoutPosition = raf.readShort();
      os_2.sFamilyClass = raf.readShort();
      raf.readFully(os_2.panose);
      raf.skipBytes(16);
      raf.readFully(os_2.achVendID);
      os_2.fsSelection = raf.readUnsignedShort();
      os_2.usFirstCharIndex = raf.readUnsignedShort();
      os_2.usLastCharIndex = raf.readUnsignedShort();
      os_2.sTypoAscender = raf.readShort();
      os_2.sTypoDescender = raf.readShort();
      if (os_2.sTypoDescender > 0) os_2.sTypoDescender = -os_2.sTypoDescender;
      os_2.sTypoLineGap = raf.readShort();
      os_2.usWinAscent = raf.readUnsignedShort();
      os_2.usWinDescent = raf.readUnsignedShort();
      os_2.ulCodePageRange1 = raf.readInt();
      os_2.ulCodePageRange2 = raf.readInt();
      if (version >= 2) {
        os_2.sxHeight = raf.readShort();
        os_2.sCapHeight = raf.readShort();
      }
    }
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
      if (format == 12) cmaps.cmap310 = readFormat12();
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

  Map<int, List<int>> readFormat12() {
    Map<int, List<int>> h = {};
    raf.skipBytes(2); // reserved
    raf.readInt(); // length
    raf.readInt(); // language
    int nGroups = raf.readInt();
    for (int k = 0; k < nGroups; k++) {
      int startCharCode = raf.readInt();
      int endCharCode = raf.readInt();
      int startGlyphID = raf.readInt();
      for (int i = startCharCode; i <= endCharCode; i++) {
        int glyph = startGlyphID + (i - startCharCode);
        h[i] = [glyph, getGlyphWidth(glyph)];
      }
    }
    return h;
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

    // TODO: Ideally implementing optimized full access.
    // For now, let's just re-read the file or return bytes if array source.

    // We will assume array source if we can
    int len = raf.length();
    Uint8List buf = Uint8List(len);
    int pos = raf.getPosition();
    raf.seek(0);
    raf.readFully(buf);
    raf.seek(pos);
    return buf;
  }

  FontNames getFontNames() {
    FontNames fn = FontNames();
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

  int readNumGlyphs() {
    List<int>? maxp = tables["maxp"];
    if (maxp == null) return 65536;
    raf.seek(maxp[0] + 4);
    return raf.readUnsignedShort();
  }

  List<int> getGlyphWidthsByIndex() {
    return glyphWidthsByIndex;
  }
}
