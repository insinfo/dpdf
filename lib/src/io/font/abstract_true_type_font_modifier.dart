import 'dart:typed_data';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'package:dpdf/src/io/font/pdf_encodings.dart';
import 'package:dpdf/src/commons/utils/tuple2.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

abstract class AbstractTrueTypeFontModifier {
  static const List<String> TABLE_NAMES_SUBSET = [
    "cvt ",
    "fpgm",
    "glyf",
    "head",
    "hhea",
    "hmtx",
    "loca",
    "maxp",
    "prep",
    "cmap",
    "OS/2"
  ];

  static const List<String> TABLE_NAMES = [
    "cvt ",
    "fpgm",
    "glyf",
    "head",
    "hhea",
    "hmtx",
    "loca",
    "maxp",
    "prep",
    "cmap",
    "OS/2",
    "name",
    "post"
  ];

  static const List<int> ENTRY_SELECTORS = [
    0,
    0,
    1,
    1,
    2,
    2,
    2,
    2,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    4,
    4,
    4,
    4,
    4
  ];

  static const int TABLE_CHECKSUM = 0;
  static const int TABLE_OFFSET = 1;
  static const int TABLE_LENGTH = 2;
  static const int HEAD_LOCA_FORMAT_OFFSET = 51;

  late Map<String, List<int>> tableDirectory;
  late Map<int, Uint8List> glyphDataMap;
  final Map<String, Uint8List> modifiedTables = {};
  late RandomAccessFileOrArray raf;
  late int directoryOffset;
  final String fontName;
  late Map<int, Uint8List> horizontalMetricMap;
  late int numberOfHMetrics;

  late _FontRawData _outFont;
  late List<String> _tableNames;

  AbstractTrueTypeFontModifier(this.fontName, bool subsetTables) {
    if (subsetTables) {
      _tableNames = TABLE_NAMES_SUBSET;
    } else {
      _tableNames = TABLE_NAMES;
    }
  }

  Tuple2<int, Uint8List> process() {
    try {
      _createTableDirectory();
      int numberOfGlyphs = mergeTables();
      _assembleFont();
      return Tuple2<int, Uint8List>(numberOfGlyphs, _outFont.getData());
    } finally {
      raf.close();
    }
  }

  int mergeTables();

  int createModifiedTables() {
    List<int> activeGlyphs = glyphDataMap.keys.toList();
    int glyfSize = 0;
    for (var data in glyphDataMap.values) {
      glyfSize += data.length;
    }
    activeGlyphs.sort();
    int maxGlyphId = activeGlyphs.last;

    int locaSize = maxGlyphId + 2;
    bool isLocaShortTable = _isLocaShortTable();
    int newLocaTableSize = isLocaShortTable ? locaSize * 2 : locaSize * 4;
    Uint8List newLoca = Uint8List(newLocaTableSize);
    Uint8List newGlyf = Uint8List(glyfSize);
    int glyfPtr = 0;
    int listGlyfIdx = 0;

    for (int k = 0; k < locaSize; ++k) {
      _writeToLoca(newLoca, k, glyfPtr, isLocaShortTable);
      if (listGlyfIdx < activeGlyphs.length && activeGlyphs[listGlyfIdx] == k) {
        int glyphId = activeGlyphs[listGlyfIdx];
        listGlyfIdx++;
        Uint8List glyphData = glyphDataMap[glyphId]!;
        newGlyf.setRange(glyfPtr, glyfPtr + glyphData.length, glyphData);
        glyfPtr += glyphData.length;
      }
    }
    modifiedTables["glyf"] = newGlyf;
    modifiedTables["loca"] = newLoca;

    List<int> tableLocation = tableDirectory["maxp"]!;
    raf.seek(tableLocation[TABLE_OFFSET]);
    Uint8List maxp = Uint8List(tableLocation[TABLE_LENGTH]);
    raf.readFully(maxp);
    _writeShortToTable(maxp, 2, maxGlyphId + 1);
    modifiedTables["maxp"] = maxp;

    if (numberOfHMetrics > maxGlyphId + 1) {
      List<int> hheaTableLocation = tableDirectory["hhea"]!;
      raf.seek(hheaTableLocation[TABLE_OFFSET]);
      Uint8List hhea = Uint8List(hheaTableLocation[TABLE_LENGTH]);
      raf.readFully(hhea);
      _writeShortToTable(hhea, 17, maxGlyphId + 1);
      modifiedTables["hhea"] = hhea;
    }

    Uint8List newHmtx = _createNewHorizontalMetricsTable(maxGlyphId);
    modifiedTables["hmtx"] = newHmtx;

    return maxGlyphId + 1;
  }

  Uint8List _createNewHorizontalMetricsTable(int maxGlyphId) {
    List<int> tableLocation = tableDirectory["hmtx"]!;
    BytesBuilder bb = BytesBuilder();
    raf.seek(tableLocation[TABLE_OFFSET]);
    for (int k = 0; k < numberOfHMetrics; ++k) {
      if (k > maxGlyphId) break;
      if (horizontalMetricMap.containsKey(k)) {
        raf.skipBytes(4);
        bb.add(horizontalMetricMap[k]!);
      } else {
        bb.addByte(raf.readUnsignedByte());
        bb.addByte(raf.readUnsignedByte());
        bb.addByte(raf.readUnsignedByte());
        bb.addByte(raf.readUnsignedByte());
      }
    }

    for (int k = numberOfHMetrics; k <= maxGlyphId; ++k) {
      if (horizontalMetricMap.containsKey(k)) {
        bb.add(horizontalMetricMap[k]!);
      } else {
        bb.add(Uint8List(2));
      }
    }
    return bb.toBytes();
  }

  void _createTableDirectory() {
    tableDirectory = {};
    raf.seek(directoryOffset);
    int id = raf.readInt();
    if (id != 0x00010000) {
      throw IoException(IoExceptionMessageConstant.notAtTrueTypeFile)
          .setMessageParams([fontName]);
    }
    int numTables = raf.readUnsignedShort();
    raf.skipBytes(6);
    for (int k = 0; k < numTables; ++k) {
      String tag = _readTag();
      List<int> tableLocation = List.filled(3, 0);
      tableLocation[TABLE_CHECKSUM] = raf.readInt();
      tableLocation[TABLE_OFFSET] = raf.readInt();
      tableLocation[TABLE_LENGTH] = raf.readInt();
      tableDirectory[tag] = tableLocation;
    }
  }

  bool _isLocaShortTable() {
    List<int>? tableLocation = tableDirectory["head"];
    if (tableLocation == null) {
      throw IoException(IoExceptionMessageConstant.tableDoesNotExistsIn)
          .setMessageParams(["head", fontName]);
    }
    raf.seek(tableLocation[TABLE_OFFSET] + HEAD_LOCA_FORMAT_OFFSET);
    return raf.readUnsignedShort() == 0;
  }

  void _assembleFont() {
    int tablesUsed = 0;
    int fullFontSize = 0;

    for (String name in _tableNames) {
      if (modifiedTables.containsKey(name)) {
        tablesUsed++;
        fullFontSize += (modifiedTables[name]!.length + 3) & ~3;
      } else {
        List<int>? tableLocation = tableDirectory[name];
        if (tableLocation != null) {
          tablesUsed++;
          fullFontSize += (tableLocation[TABLE_LENGTH] + 3) & ~3;
        }
      }
    }

    int reference = 16 * tablesUsed + 12;
    fullFontSize += reference;
    _outFont = _FontRawData(fullFontSize);

    _outFont.writeFontInt(0x00010000);
    _outFont.writeFontShort(tablesUsed);
    int selector = ENTRY_SELECTORS[tablesUsed];
    _outFont.writeFontShort((1 << selector) * 16);
    _outFont.writeFontShort(selector);
    _outFont.writeFontShort((tablesUsed - (1 << selector)) * 16);

    for (String name in _tableNames) {
      int len;
      List<int>? tableLocation = tableDirectory[name];
      if (tableLocation == null && !modifiedTables.containsKey(name)) continue;

      _outFont.writeFontString(name);
      if (modifiedTables.containsKey(name)) {
        Uint8List table = modifiedTables[name]!;
        _outFont.writeFontInt(_calculateChecksum(table));
        len = table.length;
      } else {
        _outFont.writeFontInt(tableLocation![TABLE_CHECKSUM]);
        len = tableLocation[TABLE_LENGTH];
      }
      _outFont.writeFontInt(reference);
      _outFont.writeFontInt(len);
      reference += (len + 3) & ~3;
    }

    for (String name in _tableNames) {
      if (modifiedTables.containsKey(name)) {
        _outFont.writeFontTable(modifiedTables[name]!);
      } else {
        List<int>? tableLocation = tableDirectory[name];
        if (tableLocation != null) {
          raf.seek(tableLocation[TABLE_OFFSET]);
          _outFont.writeFontTableFromRaf(raf, tableLocation[TABLE_LENGTH]);
        }
      }
    }
  }

  String _readTag() {
    Uint8List buf = Uint8List(4);
    raf.readFully(buf);
    return PdfEncodings.convertToString(buf, PdfEncodings.WINANSI);
  }

  static void _writeToLoca(
      Uint8List loca, int index, int location, bool isLocaShortTable) {
    if (isLocaShortTable) {
      index *= 2;
      location ~/= 2;
      loca[index] = (location >> 8) & 0xFF;
      loca[index + 1] = location & 0xFF;
    } else {
      index *= 4;
      loca[index] = (location >> 24) & 0xFF;
      loca[index + 1] = (location >> 16) & 0xFF;
      loca[index + 2] = (location >> 8) & 0xFF;
      loca[index + 3] = location & 0xFF;
    }
  }

  static void _writeShortToTable(Uint8List table, int index, int data) {
    index *= 2;
    table[index] = (data >> 8) & 0xFF;
    table[index + 1] = data & 0xFF;
  }

  int _calculateChecksum(Uint8List b) {
    int len = b.length ~/ 4;
    int v0 = 0;
    int v1 = 0;
    int v2 = 0;
    int v3 = 0;
    int ptr = 0;
    for (int k = 0; k < len; ++k) {
      v3 += b[ptr++] & 0xff;
      v2 += b[ptr++] & 0xff;
      v1 += b[ptr++] & 0xff;
      v0 += b[ptr++] & 0xff;
    }
    // Note: C# uses signed int for checksum. Dart's ints are 64-bit.
    // We should mask to 32-bit if needed, but the original seems to just sum.
    // Actually the return is int.
    return (v0 & 0xFF) |
        ((v1 & 0xFF) << 8) |
        ((v2 & 0xFF) << 16) |
        ((v3 & 0xFF) << 24);
  }
}

class _FontRawData {
  final Uint8List _data;
  int _ptr = 0;

  _FontRawData(int size) : _data = Uint8List(size);

  Uint8List getData() => _data;

  void writeFontTableFromRaf(RandomAccessFileOrArray raf, int tableLength) {
    raf.readFullyInto(_data, _ptr, tableLength);
    _ptr += (tableLength + 3) & ~3;
  }

  void writeFontTable(Uint8List tableData) {
    _data.setRange(_ptr, _ptr + tableData.length, tableData);
    _ptr += (tableData.length + 3) & ~3;
  }

  void writeFontShort(int n) {
    _data[_ptr++] = (n >> 8) & 0xFF;
    _data[_ptr++] = n & 0xFF;
  }

  void writeFontInt(int n) {
    _data[_ptr++] = (n >> 24) & 0xFF;
    _data[_ptr++] = (n >> 16) & 0xFF;
    _data[_ptr++] = (n >> 8) & 0xFF;
    _data[_ptr++] = n & 0xFF;
  }

  void writeFontString(String s) {
    Uint8List b = PdfEncodings.convertToBytes(s, PdfEncodings.WINANSI);
    _data.setRange(_ptr, _ptr + b.length, b);
    _ptr += b.length;
  }
}
