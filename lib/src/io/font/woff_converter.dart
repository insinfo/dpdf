import 'dart:typed_data';

import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';
import 'package:dpdf/src/io/font/woff2_converter.dart';
import 'package:dpdf/src/platform/compression.dart';

/// Rebuilds the sfnt font that a WOFF 1.0 file wraps.
///
/// ISO 32000-1:2008, 9.9 embeds font programs as sfnt data: a table
/// directory followed by the tables themselves. WOFF (W3C, "WOFF File
/// Format 1.0") stores exactly those tables, in tag order, each optionally
/// deflated on its own, behind a wider directory that also records the
/// original length and checksum. Undoing the wrapper therefore restores a
/// byte-faithful font program, which every other part of this package --
/// the sfnt parser and the subsetter included -- can read unchanged.
///
/// WOFF 2.0 is a different problem: it compresses the whole table stream
/// with Brotli and rewrites `glyf`, `loca` and `hmtx` into a transformed
/// encoding. [Woff2Converter] undoes that, and [toSfnt] hands the file over
/// to it, so a caller can unwrap either generation the same way.
abstract final class WoffConverter {
  static const int _woffSignature = 0x774f4646; // 'wOFF'
  static const int _woff2Signature = 0x774f4632; // 'wOF2'
  static const int _headerLength = 44;
  static const int _woffEntryLength = 20;
  static const int _sfntEntryLength = 16;

  /// Whether [data] begins with the WOFF 1.0 signature.
  static bool isWoff(List<int> data) => _signature(data) == _woffSignature;

  /// Whether [data] begins with the WOFF 2.0 signature.
  static bool isWoff2(List<int> data) => _signature(data) == _woff2Signature;

  static int? _signature(List<int> data) {
    if (data.length < 4) return null;
    return (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
  }

  /// Returns the sfnt font inside [data], or [data] itself when it is not a
  /// WOFF file of either generation. A WOFF 2.0 file that wraps a TrueType
  /// collection comes back as a collection, which the sfnt reader of this
  /// package does not open on its own.
  static Uint8List toSfnt(Uint8List data) {
    if (isWoff2(data)) return Woff2Converter.convert(data);
    return isWoff(data) ? convert(data) : data;
  }

  /// Rebuilds the sfnt font held by the WOFF 1.0 file [data].
  static Uint8List convert(Uint8List data) {
    final source = ByteData.sublistView(data);
    if (data.length < _headerLength ||
        source.getUint32(0) != _woffSignature ||
        source.getUint16(14) != 0) {
      throw IoException(IoExceptionMessageConstant.invalidWoffFile);
    }
    final flavor = source.getUint32(4);
    final length = source.getUint32(8);
    final tableCount = source.getUint16(12);
    final declaredSfntSize = source.getUint32(16);
    if (length != data.length || tableCount == 0) {
      throw IoException(IoExceptionMessageConstant.invalidWoffFile);
    }
    final directoryEnd = _headerLength + tableCount * _woffEntryLength;
    if (directoryEnd > data.length) {
      throw IoException(IoExceptionMessageConstant.invalidWoffFile);
    }

    // The private and metadata blocks are not part of the font program, but
    // they must not overlap it, and a table must not reach into them.
    _checkBlock(source.getUint32(24), source.getUint32(28), data.length);
    _checkBlock(source.getUint32(36), source.getUint32(40), data.length);

    final tables = <_WoffTable>[];
    var previousTag = -1;
    for (var index = 0; index < tableCount; index++) {
      final entry = _headerLength + index * _woffEntryLength;
      final tag = source.getUint32(entry);
      final offset = source.getUint32(entry + 4);
      final compressed = source.getUint32(entry + 8);
      final original = source.getUint32(entry + 12);
      final checksum = source.getUint32(entry + 16);
      // The format requires ascending, unrepeated tags, which is also what
      // makes an sfnt directory searchable by binary search.
      if (tag <= previousTag ||
          compressed > original ||
          offset < directoryEnd ||
          offset > data.length - compressed) {
        throw IoException(IoExceptionMessageConstant.invalidWoffFile);
      }
      previousTag = tag;
      tables.add(_WoffTable(tag, offset, compressed, original, checksum));
    }

    var cursor = 12 + tableCount * _sfntEntryLength;
    for (final table in tables) {
      table.target = cursor;
      cursor += (table.originalLength + 3) & ~3;
    }
    if (declaredSfntSize != cursor) {
      throw IoException(IoExceptionMessageConstant.invalidWoffFile);
    }

    final font = Uint8List(cursor);
    final directory = ByteData.sublistView(font);
    directory.setUint32(0, flavor);
    directory.setUint16(4, tableCount);
    // searchRange, entrySelector and rangeShift restate the table count for
    // a binary search; they are derived, never read from the WOFF file.
    var entrySelector = 0;
    while (1 << (entrySelector + 1) <= tableCount) {
      entrySelector++;
    }
    final searchRange = (1 << entrySelector) * _sfntEntryLength;
    directory.setUint16(6, searchRange);
    directory.setUint16(8, entrySelector);
    directory.setUint16(10, tableCount * _sfntEntryLength - searchRange);

    for (var index = 0; index < tables.length; index++) {
      final table = tables[index];
      final entry = 12 + index * _sfntEntryLength;
      directory.setUint32(entry, table.tag);
      directory.setUint32(entry + 4, table.checksum);
      directory.setUint32(entry + 8, table.target);
      directory.setUint32(entry + 12, table.originalLength);
      font.setRange(table.target, table.target + table.originalLength,
          _tableData(data, table));
    }
    return font;
  }

  static void _checkBlock(int offset, int length, int total) {
    if (length == 0) return;
    if (offset < _headerLength || offset > total - length) {
      throw IoException(IoExceptionMessageConstant.invalidWoffFile);
    }
  }

  static Uint8List _tableData(Uint8List data, _WoffTable table) {
    final raw =
        Uint8List.sublistView(data, table.offset, table.offset + table.length);
    if (table.length == table.originalLength) return raw;
    final List<int> inflated;
    try {
      inflated = ZLibDecoder().convert(raw);
    } catch (cause) {
      throw IoException(IoExceptionMessageConstant.invalidWoffFile, cause);
    }
    if (inflated.length != table.originalLength) {
      throw IoException(IoExceptionMessageConstant.invalidWoffFile);
    }
    return inflated is Uint8List ? inflated : Uint8List.fromList(inflated);
  }
}

class _WoffTable {
  final int tag;
  final int offset;
  final int length;
  final int originalLength;
  final int checksum;
  int target = 0;

  _WoffTable(
      this.tag, this.offset, this.length, this.originalLength, this.checksum);
}
