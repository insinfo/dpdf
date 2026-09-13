import 'dart:typed_data';

import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';
import 'package:dpdf/src/io/font/open_type_parser.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';

/// One table of a font collection, as a directory entry names it.
class TrueTypeCollectionTable {
  /// The four-character table tag, `glyf` or `cmap` and so on.
  final String tag;

  /// The checksum the directory records for the table.
  final int checksum;

  /// Where the table lies, counted from the start of the collection file.
  final int offset;

  /// How many bytes the table holds, padding excluded.
  final int length;

  const TrueTypeCollectionTable(
      this.tag, this.checksum, this.offset, this.length);

  /// Whether [other] names the very same bytes of the collection file, which
  /// is how two fonts share a table.
  bool sameSpanAs(TrueTypeCollectionTable other) =>
      offset == other.offset && length == other.length;

  @override
  String toString() => '$tag@$offset+$length';
}

/// What one font of a collection says about itself, read without loading the
/// font.
///
/// Only the table directory and the `name` table are touched, so a caller can
/// list a collection of a hundred fonts and then open the one it wants.
class TrueTypeCollectionEntry {
  /// The position of this font in the collection.
  final int index;

  /// Where this font's table directory starts in the collection file.
  final int directoryOffset;

  /// The `sfntVersion` of the directory: 0x00010000 for TrueType outlines,
  /// 'OTTO' for CFF ones.
  final int sfntVersion;

  /// Name ID 6, the PostScript name.
  final String postScriptName;

  /// Name ID 4, the full font name.
  final String fullName;

  /// Name ID 1, the family name.
  final String familyName;

  /// Name ID 2, the subfamily (style) name.
  final String subfamilyName;

  /// The tables this font's directory names, in directory order.
  final List<TrueTypeCollectionTable> tables;

  TrueTypeCollectionEntry({
    required this.index,
    required this.directoryOffset,
    required this.sfntVersion,
    required this.postScriptName,
    required this.fullName,
    required this.familyName,
    required this.subfamilyName,
    required List<TrueTypeCollectionTable> tables,
  }) : tables = List.unmodifiable(tables);

  /// Whether the outlines of this font are CFF rather than TrueType.
  bool get isCff => sfntVersion == 0x4f54544f;

  /// The tags this font's directory names.
  List<String> get tableTags => [for (final table in tables) table.tag];

  /// Whether [name] identifies this font, ignoring case: the PostScript name,
  /// the full name, the family name, or family and subfamily joined by a
  /// space, which is how a full name is usually spelled.
  bool matches(String name) {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return false;
    if (wanted == postScriptName.toLowerCase()) return true;
    if (wanted == fullName.toLowerCase()) return true;
    if (wanted == familyName.toLowerCase()) return true;
    final composed = '$familyName $subfamilyName'.trim().toLowerCase();
    return composed.isNotEmpty && wanted == composed;
  }

  @override
  String toString() => '#$index ${postScriptName.isEmpty ? fullName : ''
      '$postScriptName'} (${tables.length} tables at $directoryOffset)';
}

/// Reads an OpenType font collection -- a `ttcf` file, TTC or OTC.
///
/// The OpenType specification, "Font Collections", defines a collection as "a
/// single TTC header table, one or more table directories (each corresponding
/// to a different font resource), and a number of OpenType tables", the point
/// of the format being that "font tables that are identical between two or
/// more fonts [can] be shared". Two directories may therefore name one and the
/// same table: the tables meant to be shared are "those that define glyph and
/// instruction data or use glyph indices to access data: 'glyf', 'loca',
/// 'hmtx', 'hdmx', LTSH, 'cvt ', 'fpgm', 'prep', EBLC, EBDT, EBSC, 'maxp'",
/// while `cmap`, `name` and OS/2 identify each font separately.
///
/// This reader never copies a table. Every font it opens reads the one buffer
/// the collection was built from, at the offsets its own directory gives --
/// "the table offsets in all table directories within a TTC file are measured
/// from the beginning of the TTC file" -- so a shared table is read once, in
/// place, however many fonts name it. The only copy made is [extractSfnt],
/// which is what a caller asks for when it needs one font as a file of its
/// own, such as a PDF font stream.
///
/// Both header versions are read. Version 1.0 ends with the array of table
/// directory offsets; version 2.0 adds `dsigTag`, `dsigLength` and
/// `dsigOffset`, "left null" when the collection carries no signature.
class TrueTypeCollection {
  /// 'ttcf', the collection identification tag.
  static const int ttcTag = 0x74746366;

  /// 'DSIG', the value `dsigTag` carries when a signature is present.
  static const int dsigTableTag = 0x44534947;

  static const int _headerLength = 12;
  static const int _dsigFieldsLength = 12;
  static const int _directoryEntryLength = 16;

  final Uint8List _data;
  final List<int> _directoryOffsets;
  final List<List<TrueTypeCollectionTable>> _directories;
  final Map<int, TrueTypeCollectionEntry> _entries = {};
  final Map<int, TrueTypeFont> _fonts = {};

  /// The major version of the TTC header: 1 or 2.
  final int majorVersion;

  /// The minor version of the TTC header, 0 in both defined versions.
  final int minorVersion;

  /// `dsigTag`, 0 when the collection is unsigned or the header is version 1.
  final int dsigTag;

  /// `dsigLength`, the length in bytes of the DSIG table.
  final int dsigLength;

  /// `dsigOffset`, the position of the DSIG table in the collection file.
  final int dsigOffset;

  TrueTypeCollection._(
    this._data,
    this._directoryOffsets,
    this._directories, {
    required this.majorVersion,
    required this.minorVersion,
    required this.dsigTag,
    required this.dsigLength,
    required this.dsigOffset,
  });

  /// Whether [data] begins with the `ttcf` tag.
  static bool isCollection(List<int> data) {
    if (data.length < 4) return false;
    return data[0] == 0x74 &&
        data[1] == 0x74 &&
        data[2] == 0x63 &&
        data[3] == 0x66;
  }

  /// Reads the collection held in [data].
  ///
  /// The whole header and every table directory are checked against the
  /// length of the file before anything else happens, so that a later read
  /// cannot run off the end of a truncated collection.
  factory TrueTypeCollection.fromBytes(Uint8List data) {
    if (!isCollection(data) || data.length < _headerLength) {
      throw _invalid(data.length);
    }
    final view = ByteData.sublistView(data);
    final majorVersion = view.getUint16(4);
    final minorVersion = view.getUint16(6);
    // "If the major version is not recognized, the implementation must not
    // read the table as it can make no assumptions regarding interpretation
    // of the binary data."
    if (majorVersion != 1 && majorVersion != 2) throw _invalid(data.length);
    final numFonts = view.getUint32(8);
    // A collection delivers "multiple OpenType font resources"; a count of
    // zero names no table directory at all and cannot be read as a font.
    if (numFonts == 0) throw _invalid(data.length);
    final arrayEnd = _headerLength + numFonts * 4;
    if (arrayEnd > data.length) throw _invalid(data.length);

    final offsets = <int>[];
    final directories = <List<TrueTypeCollectionTable>>[];
    for (var font = 0; font < numFonts; font++) {
      final offset = view.getUint32(_headerLength + font * 4);
      offsets.add(offset);
      directories.add(_readDirectory(view, data.length, offset));
    }

    var dsigTag = 0;
    var dsigLength = 0;
    var dsigOffset = 0;
    if (majorVersion == 2 && arrayEnd + _dsigFieldsLength <= data.length) {
      // Version 2.0 "can be used for TTC files with or without digital
      // signatures -- if there's no signature, then the last three fields of
      // the version 2.0 header are left null." Files that stop right after
      // the offset array are read as unsigned rather than rejected, because
      // an absent signature is exactly what null fields stand for.
      dsigTag = view.getUint32(arrayEnd);
      dsigLength = view.getUint32(arrayEnd + 4);
      dsigOffset = view.getUint32(arrayEnd + 8);
      if (dsigTag != 0 && dsigTag != dsigTableTag) throw _invalid(data.length);
      if (dsigTag != 0 &&
          (dsigOffset > data.length || dsigLength > data.length - dsigOffset)) {
        throw _invalid(data.length);
      }
    }

    return TrueTypeCollection._(data, offsets, directories,
        majorVersion: majorVersion,
        minorVersion: minorVersion,
        dsigTag: dsigTag,
        dsigLength: dsigLength,
        dsigOffset: dsigOffset);
  }

  static List<TrueTypeCollectionTable> _readDirectory(
      ByteData view, int fileLength, int offset) {
    if (offset > fileLength - _headerLength) throw _invalid(fileLength);
    final numTables = view.getUint16(offset + 4);
    final recordsEnd = offset + _headerLength + numTables * 16;
    if (recordsEnd > fileLength) throw _invalid(fileLength);
    final tables = <TrueTypeCollectionTable>[];
    for (var index = 0; index < numTables; index++) {
      final record = offset + _headerLength + index * 16;
      final tag =
          String.fromCharCodes(Uint8List.sublistView(view, record, record + 4));
      final checksum = view.getUint32(record + 4);
      final tableOffset = view.getUint32(record + 8);
      final length = view.getUint32(record + 12);
      if (tableOffset > fileLength || length > fileLength - tableOffset) {
        throw _invalid(fileLength);
      }
      tables.add(TrueTypeCollectionTable(tag, checksum, tableOffset, length));
    }
    return tables;
  }

  static IoException _invalid(int length) =>
      IoException(IoExceptionMessageConstant.invalidTtcFile)
          .setMessageParams(['a $length byte font collection']);

  /// How many fonts the collection holds, the `numFonts` field.
  int get numFonts => _directoryOffsets.length;

  /// The header version as a packed major/minor value: 0x00010000 or
  /// 0x00020000.
  int get version => (majorVersion << 16) | minorVersion;

  /// Where each font's table directory starts, in collection order.
  List<int> get directoryOffsets => List.unmodifiable(_directoryOffsets);

  /// Whether the header names a DSIG table. Only version 2.0 can.
  bool get hasDigitalSignature => dsigTag == dsigTableTag && dsigLength > 0;

  /// The bytes the collection was read from. Every font opened from this
  /// collection reads this same buffer.
  Uint8List get bytes => _data;

  /// The digital signature table, or null when the collection has none.
  Uint8List? get digitalSignature => hasDigitalSignature
      ? Uint8List.sublistView(_data, dsigOffset, dsigOffset + dsigLength)
      : null;

  /// What the font at [index] says about itself.
  ///
  /// Only its directory and `name` table are read, and the answer is kept, so
  /// listing a collection costs one `name` table per font and nothing more.
  TrueTypeCollectionEntry describe(int index) {
    _checkIndex(index);
    final known = _entries[index];
    if (known != null) return known;
    final offset = _directoryOffsets[index];
    final parser = OpenTypeParser.atOffset(_data, offset, ttcIndex: index);
    parser.readNameTable();
    final entry = TrueTypeCollectionEntry(
      index: index,
      directoryOffset: offset,
      sfntVersion: ByteData.sublistView(_data).getUint32(offset),
      postScriptName: _name(parser, 6),
      fullName: _name(parser, 4),
      familyName: _name(parser, 1),
      subfamilyName: _name(parser, 2),
      tables: _directories[index],
    );
    _entries[index] = entry;
    return entry;
  }

  /// What every font of the collection says about itself.
  List<TrueTypeCollectionEntry> describeAll() =>
      [for (var index = 0; index < numFonts; index++) describe(index)];

  /// The position of the font [name] identifies, or -1 when no font of the
  /// collection answers to it. See [TrueTypeCollectionEntry.matches].
  int indexOfName(String name) {
    for (var index = 0; index < numFonts; index++) {
      if (describe(index).matches(name)) return index;
    }
    return -1;
  }

  /// The font at [index], read in place over the shared buffer.
  ///
  /// The same font is returned every time, so asking twice does not read the
  /// tables twice.
  TrueTypeFont getFont(int index) {
    _checkIndex(index);
    final known = _fonts[index];
    if (known != null) return known;
    final font = TrueTypeFont.fromCollection(_data, _directoryOffsets[index],
        index: index, standaloneSfnt: () => extractSfnt(index));
    _fonts[index] = font;
    return font;
  }

  /// The font [name] identifies, by PostScript name, full name, or family
  /// name. Throws when the collection holds no such font.
  TrueTypeFont getFontByName(String name) {
    final index = indexOfName(name);
    if (index < 0) {
      throw IoException(
              IoExceptionMessageConstant.ttcIndexDoesntExistInThisTtcFile)
          .setMessageParams([name]);
    }
    return getFont(index);
  }

  /// Where each table of the font at [index] lies in the collection file.
  Map<String, int> tableOffsets(int index) {
    _checkIndex(index);
    return {
      for (final table in _directories[index]) table.tag: table.offset,
    };
  }

  /// The tags the fonts at [first] and [second] read from the same bytes.
  ///
  /// This is the sharing the format exists for: a tag listed here occupies
  /// one span of the file that both directories point at, and this reader
  /// never gives the two fonts separate copies of it.
  Set<String> sharedTables(int first, int second) {
    _checkIndex(first);
    _checkIndex(second);
    final other = {
      for (final table in _directories[second]) table.tag: table,
    };
    final shared = <String>{};
    for (final table in _directories[first]) {
      final match = other[table.tag];
      if (match != null && table.sameSpanAs(match)) shared.add(table.tag);
    }
    return shared;
  }

  /// The font at [index] as an sfnt file of its own.
  ///
  /// The tables are copied out in directory order, each starting on a
  /// four-byte boundary as "all tables must begin on four-byte boundaries,
  /// and any remaining space between tables must be padded with zeros"
  /// requires, and the directory is rewritten to the new positions. Table
  /// checksums are recomputed from the copied bytes -- they do not depend on
  /// where a table lies -- and so is the `head` table's `checksumAdjustment`,
  /// which "is not used for collection files and may be set to zero" but does
  /// count once the font stands alone.
  Uint8List extractSfnt(int index) {
    _checkIndex(index);
    final tables = _directories[index];
    final count = tables.length;
    var cursor = _headerLength + count * _directoryEntryLength;
    final positions = <int>[];
    for (final table in tables) {
      positions.add(cursor);
      cursor += (table.length + 3) & ~3;
    }

    final font = Uint8List(cursor);
    final out = ByteData.sublistView(font);
    out.setUint32(
        0, ByteData.sublistView(_data).getUint32(_directoryOffsets[index]));
    out.setUint16(4, count);
    // searchRange, entrySelector and rangeShift restate the table count for a
    // binary search; they are derived from it, never copied.
    var entrySelector = 0;
    while (1 << (entrySelector + 1) <= count) {
      entrySelector++;
    }
    final searchRange = (1 << entrySelector) * _directoryEntryLength;
    out.setUint16(6, count == 0 ? 0 : searchRange);
    out.setUint16(8, count == 0 ? 0 : entrySelector);
    out.setUint16(
        10, count == 0 ? 0 : count * _directoryEntryLength - searchRange);

    var headRecord = -1;
    for (var slot = 0; slot < count; slot++) {
      final table = tables[slot];
      final record = _headerLength + slot * _directoryEntryLength;
      font.setRange(record, record + 4, table.tag.codeUnits);
      out.setUint32(record + 8, positions[slot]);
      out.setUint32(record + 12, table.length);
      font.setRange(
          positions[slot], positions[slot] + table.length, _data, table.offset);
      if (table.tag == 'head') headRecord = record;
    }
    // "An application attempting to verify that the 'head' table has not
    // changed should calculate the checksum for that table assuming that the
    // checksumAdjustment value is zero."
    if (headRecord >= 0) {
      final head =
          positions[(headRecord - _headerLength) ~/ _directoryEntryLength];
      if (head + 12 <= font.length) out.setUint32(head + 8, 0);
    }
    for (var slot = 0; slot < count; slot++) {
      final record = _headerLength + slot * _directoryEntryLength;
      out.setUint32(record + 4,
          _checksum(font, positions[slot], (tables[slot].length + 3) & ~3));
    }
    if (headRecord >= 0) {
      final head =
          positions[(headRecord - _headerLength) ~/ _directoryEntryLength];
      if (head + 12 <= font.length) {
        out.setUint32(head + 8,
            (0xb1b0afba - _checksum(font, 0, font.length)).toUnsigned(32));
      }
    }
    return font;
  }

  static int _checksum(Uint8List font, int start, int length) {
    final view = ByteData.sublistView(font);
    var sum = 0;
    final end = start + length;
    for (var at = start; at + 4 <= end; at += 4) {
      sum = (sum + view.getUint32(at)) & 0xffffffff;
    }
    return sum;
  }

  void _checkIndex(int index) {
    if (index < 0 || index >= numFonts) {
      throw IoException(
              IoExceptionMessageConstant.ttcIndexDoesntExistInThisTtcFile)
          .setMessageParams([index]);
    }
  }

  static String _name(OpenTypeParser parser, int nameId) {
    final records = parser.allNameEntries[nameId];
    if (records == null || records.isEmpty) return '';
    // A Windows record (platform 3) is the one that is always Unicode; the
    // Macintosh ones stand in when a font carries nothing else.
    for (final record in records) {
      if (record[0] == '3') return record[3];
    }
    return records.first[3];
  }
}
