import 'dart:typed_data';
import 'dart:io';
import 'package:itext/src/io/source/random_access_file_or_array.dart';
import 'package:itext/src/io/font/font_names.dart';

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
  List<List<int>> cmapEncodings = []; // [platformID, encodingID]
  Map<int, List<int>>? cmap03;
  Map<int, List<int>>? cmap10;
  Map<int, List<int>>? cmap30;
  Map<int, List<int>>? cmap31;
  Map<int, List<int>>? cmap310;
  bool fontSpecific = false;
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
    readCmapTable();

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

  void readCmapTable() {
    // Basic implementation
    List<int>? tableLocation = tables["cmap"];
    cmaps = CmapTable();
    if (tableLocation != null) {
      raf.seek(tableLocation[0] + 2);
      int num_tables = raf.readUnsignedShort();
      for (int k = 0; k < num_tables; ++k) {
        int platformID = raf.readUnsignedShort();
        int encodingID = raf.readUnsignedShort();
        raf.readInt(); // offset
        cmaps.cmapEncodings.add([platformID, encodingID]);
        // Add logic to read specific cmaps (simplifying for now)
      }
    }
  }

  // Helpers
  FontNames getFontNames() {
    FontNames fn = FontNames();
    fn.setAllNames(allNameEntries);
    if (allNameEntries[6] != null && allNameEntries[6]!.isNotEmpty) {
      fn.setFontName(allNameEntries[6]![0][3]);
    }
    return fn;
  }

  int readNumGlyphs() {
    List<int>? maxp = tables["maxp"];
    if (maxp == null) return 65536;
    raf.seek(maxp[0] + 4);
    return raf.readUnsignedShort();
  }

  List<int> getGlyphWidthsByIndex() {
    // TODO: Implement hmtx reading
    return [];
  }
}
