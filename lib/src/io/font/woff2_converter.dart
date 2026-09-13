import 'dart:typed_data';

import 'package:dpdf/src/io/codec/brotli/brotli.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

/// Rebuilds the sfnt font that a WOFF 2.0 file carries.
///
/// WOFF 2.0 (W3C, "WOFF File Format 2.0") differs from WOFF 1.0 in two ways
/// that matter here. The table data is one Brotli stream rather than one
/// deflate stream per table, so nothing can be read until the whole block is
/// expanded; and three tables may arrive rewritten -- `glyf` and `loca`
/// into the point-oriented encoding of section 5.1, `hmtx` into the reduced
/// form of section 5.3. Undoing those rewrites is lossless: the outline of
/// every glyph, and every advance width, comes back exactly as the original
/// font had it, which is what lets the rest of this package treat the result
/// as an ordinary font program.
///
/// The file itself is never rebuilt as WOFF 2.0, so only decoding is here.
abstract final class Woff2Converter {
  static const int _signature = 0x774f4632; // 'wOF2'
  static const int _ttcFlavor = 0x74746366; // 'ttcf'
  static const int _headerLength = 48;
  static const int _sfntEntrySize = 16;

  static const int _glyfTag = 0x676c7966; // 'glyf'
  static const int _locaTag = 0x6c6f6361; // 'loca'
  static const int _hmtxTag = 0x686d7478; // 'hmtx'
  static const int _headTag = 0x68656164; // 'head'
  static const int _hheaTag = 0x68686561; // 'hhea'
  static const int _maxpTag = 0x6d617870; // 'maxp'

  // Point flags of a simple glyph, OpenType 'glyf'.
  static const int _glyfOnCurve = 0x01;
  static const int _glyfShortX = 0x02;
  static const int _glyfShortY = 0x04;
  static const int _glyfRepeat = 0x08;
  static const int _glyfSameX = 0x10;
  static const int _glyfSameY = 0x20;
  static const int _glyfOverlapSimple = 0x40;

  // Component flags of a composite glyph, OpenType 'glyf'.
  static const int _flagArgsAreWords = 0x0001;
  static const int _flagWeHaveAScale = 0x0008;
  static const int _flagMoreComponents = 0x0020;
  static const int _flagWeHaveAnXAndYScale = 0x0040;
  static const int _flagWeHaveATwoByTwo = 0x0080;
  static const int _flagWeHaveInstructions = 0x0100;

  /// The 63 tags of section 4.1, in the order the format numbers them: a
  /// directory entry names a table by its index here instead of spelling the
  /// tag out. Four characters each, padded with a space where the tag is
  /// shorter, which is how the tags are written in a font as well.
  static const String _knownTagText =
      'cmapheadhheahmtxmaxpnameOS/2postcvt fpgmglyflocaprepCFF VORGEBDT'
      'EBLCgasphdmxkernLTSHPCLTVDMXvheavmtxBASEGDEFGPOSGSUBEBSCJSTFMATH'
      'CBDTCBLCCOLRCPALSVG sbixacntavarbdatblocbslncvarfdscfeatfmtxfvar'
      'gvarhstyjustlcarmortmorxopbdproptrakZapfSilfGlatGlocFeatSill';

  /// Whether [data] begins with the WOFF 2.0 signature.
  static bool isWoff2(List<int> data) {
    if (data.length < 4) return false;
    return ((data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3]) ==
        _signature;
  }

  /// Rebuilds the font program held by the WOFF 2.0 file [data].
  ///
  /// The result is an sfnt font, or a TrueType collection when the file wraps
  /// one, with `checkSumAdjustment` recomputed so the font validates on its
  /// own terms.
  static Uint8List convert(Uint8List data) {
    final header = _Woff2Header.parse(data);
    final source = _expand(data, header);
    final writer = _SfntWriter(header.totalSfntSize);
    final fonts = _writeHeaders(header, writer);
    for (var index = 0; index < fonts.length; index++) {
      _reconstructFont(source, header, fonts, index, writer);
    }
    _applyCheckSums(header, fonts, writer);
    final font = writer.take();
    // Section 3: totalSfntSize is the size the reconstructed font must have.
    if (header.totalSfntSize != font.length) {
      throw IoException(IoExceptionMessageConstant.invalidWoff2FontFile);
    }
    return font;
  }

  /// The extended metadata block of [data], expanded, or null when the file
  /// carries none. Section 3 stores it as Brotli-compressed XML outside the
  /// font data, so it is read separately from [convert].
  static Uint8List? extractMetadata(Uint8List data) {
    final header = _Woff2Header.parse(data);
    if (header.metaLength == 0) return null;
    final block = Uint8List.sublistView(
        data, header.metaOffset, header.metaOffset + header.metaLength);
    final Uint8List metadata;
    try {
      metadata = Brotli.decode(block, maxOutputBytes: header.metaOrigLength);
    } on BrotliDecodeException catch (cause) {
      throw IoException(IoExceptionMessageConstant.brotliDecodingFailed, cause);
    }
    if (metadata.length != header.metaOrigLength) {
      throw IoException(IoExceptionMessageConstant.brotliDecodingFailed);
    }
    return metadata;
  }

  /// The private data block of [data], or null when the file carries none.
  /// Section 3 leaves its contents entirely to the font vendor, so the bytes
  /// are returned as they stand.
  static Uint8List? extractPrivateData(Uint8List data) {
    final header = _Woff2Header.parse(data);
    if (header.privLength == 0) return null;
    return Uint8List.fromList(Uint8List.sublistView(
        data, header.privOffset, header.privOffset + header.privLength));
  }

  /// Expands the compressed table block. Its expanded size is known in
  /// advance -- the directory says how long every table is -- so a stream
  /// that grows past it, or stops short of it, is rejected rather than
  /// trusted.
  static Uint8List _expand(Uint8List data, _Woff2Header header) {
    if (header.uncompressedSize == 0) {
      throw IoException(IoExceptionMessageConstant.invalidWoff2FontFile);
    }
    final block = Uint8List.sublistView(data, header.compressedOffset,
        header.compressedOffset + header.compressedLength);
    final Uint8List source;
    try {
      source = Brotli.decode(block, maxOutputBytes: header.uncompressedSize);
    } on BrotliDecodeException catch (cause) {
      throw IoException(IoExceptionMessageConstant.brotliDecodingFailed, cause);
    }
    if (source.length != header.uncompressedSize) {
      throw IoException(IoExceptionMessageConstant.brotliDecodingFailed);
    }
    return source;
  }

  /// Writes the offset table and the table directory of every font, leaving
  /// the per-table checksum, offset and length at zero: they are only known
  /// once the tables themselves have been laid out.
  static List<_FontInfo> _writeHeaders(
      _Woff2Header header, _SfntWriter writer) {
    final fonts = <_FontInfo>[];
    if (header.collection.isEmpty) {
      fonts.add(_FontInfo(
          header.flavor, List.generate(header.tables.length, (i) => i)));
    } else {
      for (final entry in header.collection) {
        fonts.add(_FontInfo(entry.flavor, entry.tableIndices));
      }
      // A collection header precedes the fonts and points at each of them.
      writer.addUint32(header.flavor);
      writer.addUint32(header.collectionVersion);
      writer.addUint32(fonts.length);
      final offsetTable = writer.length;
      for (var index = 0; index < fonts.length; index++) {
        writer.addUint32(0);
      }
      if (header.collectionVersion == 0x00020000) {
        // ulDsigTag, ulDsigLength and ulDsigOffset; the signature itself is
        // not carried across, so the three fields stay empty.
        writer.addUint32(0);
        writer.addUint32(0);
        writer.addUint32(0);
      }
      for (var index = 0; index < fonts.length; index++) {
        writer.setUint32(offsetTable + index * 4, writer.length);
        _writeFontHeader(header, fonts[index], writer);
      }
      return fonts;
    }
    _writeFontHeader(header, fonts.single, writer);
    return fonts;
  }

  static void _writeFontHeader(
      _Woff2Header header, _FontInfo font, _SfntWriter writer) {
    // The sfnt directory is ordered by tag, whatever order the WOFF file
    // listed the tables in, because that is what makes it binary-searchable.
    final sorted = List<int>.of(font.tableIndices)
      ..sort((a, b) => header.tables[a].tag.compareTo(header.tables[b].tag));
    for (var index = 1; index < sorted.length; index++) {
      if (header.tables[sorted[index]].tag ==
          header.tables[sorted[index - 1]].tag) {
        throw IoException(IoExceptionMessageConstant.readTableDirectoryFailed);
      }
    }
    font.tableIndices = sorted;
    font.headerOffset = writer.length;

    final count = sorted.length;
    writer.addUint32(font.flavor);
    writer.addUint16(count);
    var entrySelector = 0;
    while (1 << (entrySelector + 1) <= count) {
      entrySelector++;
    }
    final searchRange = (1 << entrySelector) * _sfntEntrySize;
    writer.addUint16(searchRange);
    writer.addUint16(entrySelector);
    writer.addUint16(count * _sfntEntrySize - searchRange);
    for (final index in sorted) {
      font.entryByTag[header.tables[index].tag] = writer.length;
      writer.addUint32(header.tables[index].tag);
      writer.addUint32(0); // checkSum
      writer.addUint32(0); // offset
      writer.addUint32(0); // length
    }
    font.headerLength = writer.length - font.headerOffset;
  }

  /// Lays out one font's tables and fills in its directory entries.
  static void _reconstructFont(Uint8List source, _Woff2Header header,
      List<_FontInfo> fonts, int fontIndex, _SfntWriter writer) {
    final font = fonts[fontIndex];
    _readFontDimensions(source, header, font);
    final glyf = font.indexOf(header, _glyfTag);
    final loca = font.indexOf(header, _locaTag);
    if ((glyf < 0) != (loca < 0)) {
      // A font carries either both of them or neither.
      throw IoException(
          IoExceptionMessageConstant.reconstructTableDirectoryFailed);
    }
    if (glyf >= 0 &&
        header.tables[glyf].transformed != header.tables[loca].transformed) {
      throw IoException(
          IoExceptionMessageConstant.reconstructTableDirectoryFailed);
    }

    for (var position = 0; position < font.tableIndices.length; position++) {
      final table = header.tables[font.tableIndices[position]];
      final shared = header.shared[table.key];
      if (shared != null) {
        if (fontIndex == 0) {
          // Within a single font no table may be listed twice.
          throw IoException(
              IoExceptionMessageConstant.readTableDirectoryFailed);
        }
        _writeEntry(font, table.tag, shared, writer);
        continue;
      }
      final placement =
          _writeTable(source, header, font, table, position, writer);
      header.shared[table.key] = placement;
      _writeEntry(font, table.tag, placement, writer);
      writer.padToFour();
    }
  }

  static void _writeEntry(
      _FontInfo font, int tag, _TablePlacement placement, _SfntWriter writer) {
    final entry = font.entryByTag[tag]!;
    writer.setUint32(entry + 8, placement.offset);
    writer.setUint32(entry + 12, placement.length);
  }

  /// Copies or rebuilds a single table, returning where it landed.
  static _TablePlacement _writeTable(Uint8List source, _Woff2Header header,
      _FontInfo font, _Woff2Table table, int position, _SfntWriter writer) {
    if (!table.transformed) {
      final start = writer.length;
      writer.addBytes(source, table.sourceOffset, table.sourceEnd);
      return _TablePlacement(start, table.originalLength);
    }
    switch (table.tag) {
      case _glyfTag:
        return _reconstructGlyf(source, header, font, table, position, writer);
      case _locaTag:
        // A transformed loca holds no bytes of its own: it was written out
        // together with glyf, which tag order puts ahead of it.
        final placement = font.locaPlacement;
        if (placement == null) {
          throw IoException(
              IoExceptionMessageConstant.reconstructTableDirectoryFailed);
        }
        return placement;
      case _hmtxTag:
        return _reconstructHmtx(source, font, table, writer);
      default:
        // No other table has a transformation defined for it.
        throw IoException(IoExceptionMessageConstant.readTableDirectoryFailed);
    }
  }

  /// Collects what the reconstruction needs out of tables that are never
  /// transformed themselves -- the glyph count, the number of glyphs with
  /// their own advance width, and how loca spells its offsets -- so that the
  /// order the tables appear in cannot matter.
  static void _readFontDimensions(
      Uint8List source, _Woff2Header header, _FontInfo font) {
    final maxp = font.indexOf(header, _maxpTag);
    if (maxp >= 0) {
      final table = header.tables[maxp];
      if (table.originalLength < 6) {
        throw IoException(IoExceptionMessageConstant.readHeaderFailed);
      }
      font.numGlyphs = _uint16(source, table.sourceOffset + 4);
    }
    final hhea = font.indexOf(header, _hheaTag);
    if (hhea >= 0) {
      final table = header.tables[hhea];
      if (table.originalLength < 36) {
        throw IoException(IoExceptionMessageConstant.readHeaderFailed);
      }
      font.numHMetrics = _uint16(source, table.sourceOffset + 34);
    }
    final head = font.indexOf(header, _headTag);
    if (head >= 0) {
      final table = header.tables[head];
      if (table.originalLength < 54) {
        throw IoException(IoExceptionMessageConstant.readHeaderFailed);
      }
      font.indexFormat = _uint16(source, table.sourceOffset + 50);
    }
    final glyf = font.indexOf(header, _glyfTag);
    final loca = font.indexOf(header, _locaTag);
    if (glyf >= 0 && loca >= 0 && !header.tables[glyf].transformed) {
      font.xMins =
          _readXMins(source, header.tables[glyf], header.tables[loca], font);
    }
  }

  /// The `xMin` of every glyph, read straight out of an untransformed `glyf`.
  ///
  /// A transformed `hmtx` leans on those values, and the table it leans on
  /// need not itself have been transformed, so they are collected here as
  /// well as while rebuilding a transformed `glyf`.
  static List<int> _readXMins(
      Uint8List source, _Woff2Table glyf, _Woff2Table loca, _FontInfo font) {
    const failed = IoExceptionMessageConstant.reconstructHmtxTableFailed;
    final wide = font.indexFormat != 0;
    if (loca.originalLength != (wide ? 4 : 2) * (font.numGlyphs + 1)) {
      return const <int>[];
    }
    final xMins = Int16List(font.numGlyphs);
    var previous = wide
        ? _uint32(source, loca.sourceOffset)
        : _uint16(source, loca.sourceOffset) * 2;
    for (var index = 0; index < font.numGlyphs; index++) {
      final at = loca.sourceOffset + (index + 1) * (wide ? 4 : 2);
      final next = wide ? _uint32(source, at) : _uint16(source, at) * 2;
      if (next < previous || next > glyf.originalLength) {
        throw IoException(failed);
      }
      // An empty glyph has no outline and so no left side bearing of its own.
      if (next != previous) {
        if (next - previous < 10) throw IoException(failed);
        xMins[index] = _int16(source, glyf.sourceOffset + previous + 2);
      }
      previous = next;
    }
    return xMins;
  }

  static int _uint32(Uint8List data, int offset) =>
      (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];

  static int _uint16(Uint8List data, int offset) =>
      (data[offset] << 8) | data[offset + 1];

  /// Recomputes `checkSumAdjustment` for every font, which the format leaves
  /// to the decoder because the value depends on the rebuilt tables.
  static void _applyCheckSums(
      _Woff2Header header, List<_FontInfo> fonts, _SfntWriter writer) {
    for (final font in fonts) {
      final headEntry = font.entryByTag[_headTag];
      if (headEntry != null) {
        final offset = writer.getUint32(headEntry + 8);
        if (writer.getUint32(headEntry + 12) < 12) {
          throw IoException(IoExceptionMessageConstant.invalidWoff2FontFile);
        }
        writer.setUint32(offset + 8, 0);
      }
    }
    for (final font in fonts) {
      var sum = 0;
      for (final tag in font.entryByTag.keys) {
        final entry = font.entryByTag[tag]!;
        final checksum = writer.checksum(
            writer.getUint32(entry + 8), writer.getUint32(entry + 12));
        writer.setUint32(entry + 4, checksum);
        sum = (sum + checksum) & 0xffffffff;
      }
      sum = (sum + writer.checksum(font.headerOffset, font.headerLength)) &
          0xffffffff;
      final headEntry = font.entryByTag[_headTag];
      if (headEntry != null) {
        writer.setUint32(writer.getUint32(headEntry + 8) + 8,
            (0xb1b0afba - sum) & 0xffffffff);
      }
    }
  }

  // --- transformations, filled in by the sections below -------------------

  /// Rebuilds `glyf`, and with it `loca`, from the transformed form of
  /// section 5.1.
  ///
  /// The transformation splits the table into seven streams, each holding one
  /// kind of number for every glyph in turn: contour counts, point counts,
  /// point flags, point coordinates, composite component records, bounding
  /// boxes, and hinting instructions. Reading them in step reproduces the
  /// glyphs one at a time, and their sizes give the `loca` offsets, which is
  /// why the transformed `loca` carries no bytes of its own.
  static _TablePlacement _reconstructGlyf(Uint8List source, _Woff2Header header,
      _FontInfo font, _Woff2Table table, int position, _SfntWriter writer) {
    const failed = IoExceptionMessageConstant.reconstructGlyfTableFailed;
    // loca holds no bytes of its own, so it is written out here, directly
    // behind glyf. Tag order puts it after glyf in the layout, so its entry
    // is always filled in after this table has been laid down.
    final locaIndex = font.indexOf(header, _locaTag);
    if (locaIndex < 0 || position >= font.tableIndices.indexOf(locaIndex)) {
      throw IoException(failed);
    }
    final locaTable = header.tables[locaIndex];
    if (!locaTable.transformed) throw IoException(failed);

    final file = _Woff2Reader(source, table.sourceOffset, table.sourceEnd);
    file.readUint16(failed); // reserved
    final optionFlags = file.readUint16(failed);
    final hasOverlapBitmap = (optionFlags & 0x0001) != 0;
    final numGlyphs = file.readUint16(failed);
    final indexFormat = file.readUint16(failed);
    if (numGlyphs != font.numGlyphs || indexFormat != font.indexFormat) {
      // maxp and head already said how many glyphs there are and how loca
      // spells its offsets; the transformed table must agree with them.
      throw IoException(failed);
    }
    if (locaTable.originalLength !=
        (indexFormat != 0 ? 4 : 2) * (numGlyphs + 1)) {
      throw IoException(IoExceptionMessageConstant.locaSizeOverflow);
    }

    final streams = <_Woff2Reader>[];
    var cursor = 9 * 4;
    for (var index = 0; index < 7; index++) {
      final size = file.readUint32(failed);
      if (size > table.transformLength - cursor) throw IoException(failed);
      streams.add(_Woff2Reader(source, table.sourceOffset + cursor,
          table.sourceOffset + cursor + size));
      cursor += size;
    }
    final nContours = streams[0];
    final nPoints = streams[1];
    final flags = streams[2];
    final glyphs = streams[3];
    final composites = streams[4];
    final boxes = streams[5];
    final instructions = streams[6];

    // An optional eighth stream marks the glyphs whose contours may overlap;
    // the bit becomes a flag on the first point of the rebuilt glyph.
    Uint8List? overlap;
    if (hasOverlapBitmap) {
      final size = (numGlyphs + 7) >> 3;
      if (size > table.transformLength - cursor) throw IoException(failed);
      overlap = Uint8List.sublistView(source, table.sourceOffset + cursor,
          table.sourceOffset + cursor + size);
    }

    // The bounding-box stream opens with one bit per glyph saying whether a
    // box was stored for it at all; a simple glyph without one has its box
    // computed from its own points.
    final bitmap = boxes.readBytes(((numGlyphs + 31) >> 5) << 2, failed);

    final glyfStart = writer.length;
    final locaValues = Uint32List(numGlyphs + 1);
    final xMins = Int16List(numGlyphs);
    final glyph = _SfntWriter(1024);
    for (var index = 0; index < numGlyphs; index++) {
      locaValues[index] = writer.length - glyfStart;
      final haveBox = (bitmap[index >> 3] & (0x80 >> (index & 7))) != 0;
      final contourCount = nContours.readUint16(failed);
      glyph.reset();
      if (contourCount == 0xffff) {
        _reconstructComposite(
            glyph, composites, glyphs, instructions, boxes, haveBox);
      } else if (contourCount > 0) {
        final overlapBit = overlap != null &&
            (overlap[index >> 3] & (0x80 >> (index & 7))) != 0;
        _reconstructSimpleGlyph(glyph, contourCount, nPoints, flags, glyphs,
            instructions, boxes, haveBox, overlapBit);
      } else if (haveBox) {
        // An empty glyph occupies no bytes, so it cannot carry a box.
        throw IoException(failed);
      }
      if (glyph.length != 0) {
        xMins[index] = _int16(glyph.take(), 2);
        writer.addBytes(glyph.take(), 0, glyph.length);
      }
      // Every glyph but the last begins on a four-byte boundary.
      if (index != numGlyphs - 1) writer.padToFour();
    }
    // The directory recorded how long the original table was, and a rebuild
    // that does not come to that length has gone wrong. The one thing that
    // may legitimately differ is what follows the last glyph: an encoder is
    // free to count the padding that rounds the table off, or not to.
    final produced = writer.length - glyfStart;
    final glyfLength = table.originalLength;
    if (glyfLength < produced || glyfLength > _round4(produced)) {
      throw IoException(failed);
    }
    writer.addZeros(glyfLength - produced);
    locaValues[numGlyphs] = glyfLength;

    writer.padToFour();
    final locaStart = writer.length;
    for (final value in locaValues) {
      if (indexFormat != 0) {
        writer.addUint32(value);
      } else {
        // The short form counts in two-byte words, which the four-byte
        // padding after every glyph keeps exact.
        if (value > 0x1fffe || (value & 1) != 0) {
          throw IoException(IoExceptionMessageConstant.locaSizeOverflow);
        }
        writer.addUint16(value >> 1);
      }
    }
    font.locaPlacement = _TablePlacement(locaStart, writer.length - locaStart);
    font.xMins = xMins;
    // Every stream must be spent exactly, or the glyphs and the streams
    // disagree about how many bytes a glyph took.
    for (final stream in streams) {
      if (stream.remaining != 0) throw IoException(failed);
    }
    return _TablePlacement(glyfStart, glyfLength);
  }

  /// Rebuilds one composite glyph. Its component records are copied out of
  /// the composite stream unchanged, but they still have to be walked to
  /// learn where the glyph ends and whether instructions follow it.
  static void _reconstructComposite(
      _SfntWriter glyph,
      _Woff2Reader composites,
      _Woff2Reader glyphs,
      _Woff2Reader instructions,
      _Woff2Reader boxes,
      bool haveBox) {
    const failed = IoExceptionMessageConstant.reconstructGlyphFailed;
    if (!haveBox) {
      // Nothing in a composite says where its outline lies, so its box is
      // always written out.
      throw IoException(failed);
    }
    final start = composites.offset;
    var haveInstructions = false;
    var flags = _flagMoreComponents;
    while ((flags & _flagMoreComponents) != 0) {
      flags = composites.readUint16(failed);
      haveInstructions |= (flags & _flagWeHaveInstructions) != 0;
      var arguments = 2; // the component's glyph index
      arguments += (flags & _flagArgsAreWords) != 0 ? 4 : 2;
      if ((flags & _flagWeHaveAScale) != 0) {
        arguments += 2;
      } else if ((flags & _flagWeHaveAnXAndYScale) != 0) {
        arguments += 4;
      } else if ((flags & _flagWeHaveATwoByTwo) != 0) {
        arguments += 8;
      }
      composites.skip(arguments, failed);
    }
    final size = composites.offset - start;
    composites.seek(start);

    glyph.addUint16(0xffff);
    glyph.addBytes(boxes.readBytes(8, failed), 0, 8);
    final record = composites.readBytes(size, failed);
    glyph.addBytes(record, 0, size);
    if (haveInstructions) {
      final length = _read255UShort(glyphs, failed);
      glyph.addUint16(length);
      final code = instructions.readBytes(length, failed);
      glyph.addBytes(code, 0, length);
    }
  }

  /// Rebuilds one simple glyph from the point streams.
  static void _reconstructSimpleGlyph(
      _SfntWriter glyph,
      int contourCount,
      _Woff2Reader nPoints,
      _Woff2Reader flags,
      _Woff2Reader glyphs,
      _Woff2Reader instructions,
      _Woff2Reader boxes,
      bool haveBox,
      bool overlapBit) {
    const failed = IoExceptionMessageConstant.reconstructGlyphFailed;
    final endPoints = Uint16List(contourCount);
    var total = 0;
    for (var contour = 0; contour < contourCount; contour++) {
      total += _read255UShort(nPoints, failed);
      if (total > 0x10000) throw IoException(failed);
      endPoints[contour] = total - 1;
    }
    if (total == 0) throw IoException(failed);

    final xs = Int32List(total);
    final ys = Int32List(total);
    final onCurve = Uint8List(total);
    _decodeTriplets(flags, glyphs, total, xs, ys, onCurve);
    final length = _read255UShort(glyphs, failed);

    glyph.addUint16(contourCount);
    if (haveBox) {
      glyph.addBytes(boxes.readBytes(8, failed), 0, 8);
    } else {
      // Section 5.1 lets an encoder drop a box that is exactly the extent of
      // the points, on- and off-curve alike, and have the decoder work it
      // out again. Getting this wrong shifts or clips the glyph.
      var xMin = xs[0];
      var xMax = xs[0];
      var yMin = ys[0];
      var yMax = ys[0];
      for (var point = 1; point < total; point++) {
        if (xs[point] < xMin) xMin = xs[point];
        if (xs[point] > xMax) xMax = xs[point];
        if (ys[point] < yMin) yMin = ys[point];
        if (ys[point] > yMax) yMax = ys[point];
      }
      glyph.addUint16(xMin);
      glyph.addUint16(yMin);
      glyph.addUint16(xMax);
      glyph.addUint16(yMax);
    }
    for (final endPoint in endPoints) {
      glyph.addUint16(endPoint);
    }
    glyph.addUint16(length);
    glyph.addBytes(instructions.readBytes(length, failed), 0, length);
    _storePoints(glyph, total, xs, ys, onCurve, overlapBit);
  }

  /// Turns the triplet encoding of section 5.2 back into coordinates.
  ///
  /// One flag byte per point selects, out of 128 cases, how many bits of x
  /// and of y follow and what sign each carries; between one and four further
  /// bytes hold them. The numbers are deltas from the previous point, so the
  /// absolute coordinates come from running them up.
  static void _decodeTriplets(_Woff2Reader flags, _Woff2Reader glyphs,
      int total, Int32List xs, Int32List ys, Uint8List onCurve) {
    const failed = IoExceptionMessageConstant.reconstructPointFailed;
    var x = 0;
    var y = 0;
    for (var point = 0; point < total; point++) {
      final flagByte = flags.readUint8(failed);
      onCurve[point] = (flagByte & 0x80) == 0 ? 1 : 0;
      final flag = flagByte & 0x7f;
      final int deltaX;
      final int deltaY;
      if (flag < 10) {
        deltaX = 0;
        deltaY = _withSign(flag, ((flag & 14) << 7) + glyphs.readUint8(failed));
      } else if (flag < 20) {
        deltaX = _withSign(
            flag, (((flag - 10) & 14) << 7) + glyphs.readUint8(failed));
        deltaY = 0;
      } else if (flag < 84) {
        final base = flag - 20;
        final byte = glyphs.readUint8(failed);
        deltaX = _withSign(flag, 1 + (base & 0x30) + (byte >> 4));
        deltaY = _withSign(flag >> 1, 1 + ((base & 0x0c) << 2) + (byte & 0x0f));
      } else if (flag < 120) {
        final base = flag - 84;
        final first = glyphs.readUint8(failed);
        final second = glyphs.readUint8(failed);
        deltaX = _withSign(flag, 1 + ((base ~/ 12) << 8) + first);
        deltaY = _withSign(flag >> 1, 1 + (((base % 12) >> 2) << 8) + second);
      } else if (flag < 124) {
        final first = glyphs.readUint8(failed);
        final second = glyphs.readUint8(failed);
        final third = glyphs.readUint8(failed);
        deltaX = _withSign(flag, (first << 4) + (second >> 4));
        deltaY = _withSign(flag >> 1, ((second & 0x0f) << 8) + third);
      } else {
        final first = glyphs.readUint8(failed);
        final second = glyphs.readUint8(failed);
        final third = glyphs.readUint8(failed);
        final fourth = glyphs.readUint8(failed);
        deltaX = _withSign(flag, (first << 8) + second);
        deltaY = _withSign(flag >> 1, (third << 8) + fourth);
      }
      x += deltaX;
      y += deltaY;
      if (x < -0x8000 || x > 0x7fff || y < -0x8000 || y > 0x7fff) {
        // A glyph outline is measured in signed 16-bit font units.
        throw IoException(failed);
      }
      xs[point] = x;
      ys[point] = y;
    }
  }

  /// Bit 0 of the flag tells the delta's sign; every case of the triplet
  /// table uses the same rule.
  static int _withSign(int flag, int value) => (flag & 1) != 0 ? value : -value;

  /// Writes the flags and coordinates of a simple glyph the way the `glyf`
  /// table wants them: one flag byte per point, with a repeat count where a
  /// flag recurs, then all the x deltas and then all the y deltas, each one
  /// or two bytes wide according to its flag.
  static void _storePoints(_SfntWriter glyph, int total, Int32List xs,
      Int32List ys, Uint8List onCurve, bool overlapBit) {
    final pointFlags = Uint8List(total);
    final xBytes = Uint8List(total * 2);
    var xCount = 0;
    final yBytes = Uint8List(total * 2);
    var yCount = 0;
    var lastX = 0;
    var lastY = 0;

    for (var point = 0; point < total; point++) {
      var flag = onCurve[point] != 0 ? _glyfOnCurve : 0;
      if (overlapBit && point == 0) flag |= _glyfOverlapSimple;
      final deltaX = xs[point] - lastX;
      if (deltaX == 0) {
        flag |= _glyfSameX;
      } else if (deltaX > -256 && deltaX < 256) {
        flag |= _glyfShortX | (deltaX > 0 ? _glyfSameX : 0);
        xBytes[xCount++] = deltaX.abs();
      } else {
        xBytes[xCount++] = (deltaX >> 8) & 0xff;
        xBytes[xCount++] = deltaX & 0xff;
      }
      final deltaY = ys[point] - lastY;
      if (deltaY == 0) {
        flag |= _glyfSameY;
      } else if (deltaY > -256 && deltaY < 256) {
        flag |= _glyfShortY | (deltaY > 0 ? _glyfSameY : 0);
        yBytes[yCount++] = deltaY.abs();
      } else {
        yBytes[yCount++] = (deltaY >> 8) & 0xff;
        yBytes[yCount++] = deltaY & 0xff;
      }
      lastX = xs[point];
      lastY = ys[point];
      pointFlags[point] = flag;
    }

    final flagBytes = Uint8List(total);
    var flagCount = 0;
    var point = 0;
    while (point < total) {
      final flag = pointFlags[point];
      var run = 1;
      // A repeat count is one byte and can stand for 255 further points.
      while (
          run < 256 && point + run < total && pointFlags[point + run] == flag) {
        run++;
      }
      if (run <= 2) {
        // Writing the flag twice costs exactly what the repeat form costs,
        // and is what font compilers emit, so the table comes back byte for
        // byte as the font that was compressed.
        for (var copy = 0; copy < run; copy++) {
          flagBytes[flagCount++] = flag;
        }
      } else {
        flagBytes[flagCount++] = flag | _glyfRepeat;
        flagBytes[flagCount++] = run - 1;
      }
      point += run;
    }

    glyph.addBytes(flagBytes, 0, flagCount);
    glyph.addBytes(xBytes, 0, xCount);
    glyph.addBytes(yBytes, 0, yCount);
  }

  static int _int16(Uint8List data, int offset) {
    final value = (data[offset] << 8) | data[offset + 1];
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  /// Rebuilds `hmtx` from the transformed form of section 5.3.
  ///
  /// In a font whose glyphs are outlines, a left side bearing is usually the
  /// `xMin` of the glyph's bounding box, so the transformation drops the side
  /// bearings it can recover that way and keeps only the advance widths. Two
  /// flag bits say which of the two runs -- the glyphs that have their own
  /// advance width, and the ones after them that share the last -- were left
  /// out and have to be read back off the rebuilt `glyf`.
  static _TablePlacement _reconstructHmtx(
      Uint8List source, _FontInfo font, _Woff2Table table, _SfntWriter writer) {
    const failed = IoExceptionMessageConstant.reconstructHmtxTableFailed;
    final reader = _Woff2Reader(source, table.sourceOffset, table.sourceEnd);
    final flags = reader.readUint8(failed);
    if ((flags & 0xfc) != 0) {
      // Bits 2 to 7 are reserved and have to be clear.
      throw IoException(failed);
    }
    final hasProportionalLsbs = (flags & 0x01) == 0;
    final hasMonospaceLsbs = (flags & 0x02) == 0;
    if (hasProportionalLsbs && hasMonospaceLsbs) {
      // Then nothing was left out, and the table should not claim to have
      // been transformed at all.
      throw IoException(failed);
    }
    final numGlyphs = font.numGlyphs;
    final numHMetrics = font.numHMetrics;
    if (numHMetrics < 1 || numHMetrics > numGlyphs) {
      throw IoException(failed);
    }
    if (font.xMins.length != numGlyphs) {
      // The side bearings that were dropped only exist as glyph bounding
      // boxes, so a font without a glyf table cannot supply them.
      throw IoException(failed);
    }

    final widths = Uint16List(numHMetrics);
    for (var index = 0; index < numHMetrics; index++) {
      widths[index] = reader.readUint16(failed);
    }
    final bearings = Int16List(numGlyphs);
    for (var index = 0; index < numHMetrics; index++) {
      bearings[index] =
          hasProportionalLsbs ? reader.readInt16(failed) : font.xMins[index];
    }
    for (var index = numHMetrics; index < numGlyphs; index++) {
      bearings[index] =
          hasMonospaceLsbs ? reader.readInt16(failed) : font.xMins[index];
    }
    if (reader.remaining != 0) throw IoException(failed);

    final start = writer.length;
    for (var index = 0; index < numGlyphs; index++) {
      if (index < numHMetrics) writer.addUint16(widths[index]);
      writer.addUint16(bearings[index]);
    }
    final length = writer.length - start;
    if (length != table.originalLength) {
      // The directory said how long the original table was; a rebuild that
      // does not come to the same length has gone wrong.
      throw IoException(failed);
    }
    return _TablePlacement(start, length);
  }
}

/// Where a rebuilt table ended up in the output font.
class _TablePlacement {
  final int offset;
  final int length;

  const _TablePlacement(this.offset, this.length);
}

/// One entry of the WOFF 2.0 table directory, section 4.1.
class _Woff2Table {
  final int tag;
  final int originalLength;
  final int transformLength;
  final bool transformed;
  final int sourceOffset;

  _Woff2Table(this.tag, this.originalLength, this.transformLength,
      this.transformed, this.sourceOffset);

  int get sourceEnd => sourceOffset + transformLength;

  /// Identifies a table well enough to notice that two fonts of a collection
  /// share it: same tag, same place in the compressed block.
  String get key => '$tag@$sourceOffset';
}

/// A font of a collection, or the single font of an ordinary file.
class _FontInfo {
  final int flavor;
  List<int> tableIndices;
  final Map<int, int> entryByTag = <int, int>{};
  int headerOffset = 0;
  int headerLength = 0;
  int numGlyphs = 0;
  int numHMetrics = 0;
  int indexFormat = 0;
  List<int> xMins = const <int>[];
  _TablePlacement? locaPlacement;

  _FontInfo(this.flavor, this.tableIndices);

  int indexOf(_Woff2Header header, int tag) {
    for (final index in tableIndices) {
      if (header.tables[index].tag == tag) return index;
    }
    return -1;
  }
}

/// One font of a WOFF 2.0 collection directory, section 6.
class _CollectionEntry {
  final int flavor;
  final List<int> tableIndices;

  const _CollectionEntry(this.flavor, this.tableIndices);
}

/// The WOFF 2.0 file header and table directory, sections 3, 4 and 6.
class _Woff2Header {
  final int flavor;
  final int totalSfntSize;
  final int compressedOffset;
  final int compressedLength;
  final int uncompressedSize;
  final int metaOffset;
  final int metaLength;
  final int metaOrigLength;
  final int privOffset;
  final int privLength;
  final int collectionVersion;
  final List<_Woff2Table> tables;
  final List<_CollectionEntry> collection;
  final Map<String, _TablePlacement> shared = <String, _TablePlacement>{};

  _Woff2Header._({
    required this.flavor,
    required this.totalSfntSize,
    required this.compressedOffset,
    required this.compressedLength,
    required this.uncompressedSize,
    required this.metaOffset,
    required this.metaLength,
    required this.metaOrigLength,
    required this.privOffset,
    required this.privLength,
    required this.collectionVersion,
    required this.tables,
    required this.collection,
  });

  static _Woff2Header parse(Uint8List data) {
    final reader = _Woff2Reader(data);
    if (data.length < Woff2Converter._headerLength ||
        reader.readUint32(IoExceptionMessageConstant.readHeaderFailed) !=
            Woff2Converter._signature) {
      throw IoException(IoExceptionMessageConstant.incorrectSignature);
    }
    const failed = IoExceptionMessageConstant.readHeaderFailed;
    final flavor = reader.readUint32(failed);
    if (reader.readUint32(failed) != data.length) {
      throw IoException(failed);
    }
    final tableCount = reader.readUint16(failed);
    if (tableCount == 0 || reader.readUint16(failed) != 0) {
      throw IoException(failed);
    }
    final totalSfntSize = reader.readUint32(failed);
    final compressedLength = reader.readUint32(failed);
    reader.skip(4, failed); // majorVersion, minorVersion
    final metaOffset = reader.readUint32(failed);
    final metaLength = reader.readUint32(failed);
    final metaOrigLength = reader.readUint32(failed);
    final privOffset = reader.readUint32(failed);
    final privLength = reader.readUint32(failed);
    _checkBlock(metaOffset, metaLength, data.length);
    _checkBlock(privOffset, privLength, data.length);
    if (metaLength != 0 && metaOrigLength == 0) {
      throw IoException(failed);
    }

    final tables = _readDirectory(reader, tableCount);
    final last = tables.last;
    final uncompressedSize = last.sourceEnd;

    var collectionVersion = 0;
    final collection = <_CollectionEntry>[];
    if (flavor == Woff2Converter._ttcFlavor) {
      collectionVersion = reader
          .readUint32(IoExceptionMessageConstant.readCollectionHeaderFailed);
      _readCollection(reader, collectionVersion, tables, collection);
    }

    final compressedOffset = reader.offset;
    var end = _round4(compressedOffset + compressedLength);
    if (end > data.length) {
      throw IoException(failed);
    }
    // The blocks that follow the font data are laid out in a fixed order
    // with no room between them.
    if (metaOffset != 0) {
      if (metaOffset != end) throw IoException(failed);
      end = _round4(metaOffset + metaLength);
    }
    if (privOffset != 0) {
      if (privOffset != end) throw IoException(failed);
      end = _round4(privOffset + privLength);
    }
    if (end != _round4(data.length)) {
      throw IoException(failed);
    }

    return _Woff2Header._(
      flavor: flavor,
      totalSfntSize: totalSfntSize,
      compressedOffset: compressedOffset,
      compressedLength: compressedLength,
      uncompressedSize: uncompressedSize,
      metaOffset: metaOffset,
      metaLength: metaLength,
      metaOrigLength: metaOrigLength,
      privOffset: privOffset,
      privLength: privLength,
      collectionVersion: collectionVersion,
      tables: tables,
      collection: collection,
    );
  }

  static void _checkBlock(int offset, int length, int total) {
    if (offset == 0) {
      if (length != 0) {
        throw IoException(IoExceptionMessageConstant.readHeaderFailed);
      }
      return;
    }
    if (offset >= total || total - offset < length) {
      throw IoException(IoExceptionMessageConstant.readHeaderFailed);
    }
  }

  static List<_Woff2Table> _readDirectory(_Woff2Reader reader, int count) {
    const failed = IoExceptionMessageConstant.readTableDirectoryFailed;
    final tables = <_Woff2Table>[];
    var sourceOffset = 0;
    for (var index = 0; index < count; index++) {
      final flags = reader.readUint8(failed);
      final knownIndex = flags & 0x3f;
      final tag = knownIndex == 0x3f
          ? reader.readUint32(failed)
          : _knownTag(knownIndex);
      final version = (flags >> 6) & 0x03;
      // For glyf and loca the null transformation is version 3 and the
      // rewritten form is version 0; every other table is the other way
      // round. Only a transformed table states its transformed length.
      final transformed =
          (tag == Woff2Converter._glyfTag || tag == Woff2Converter._locaTag)
              ? version == 0
              : version != 0;
      final originalLength = _readBase128(reader);
      var transformLength = originalLength;
      if (transformed) {
        transformLength = _readBase128(reader);
        if (tag == Woff2Converter._locaTag && transformLength != 0) {
          // loca is rebuilt from glyf, so it contributes no bytes of its own.
          throw IoException(failed);
        }
      }
      if (tag == Woff2Converter._hmtxTag && transformed && version != 1) {
        throw IoException(failed);
      }
      tables.add(_Woff2Table(
          tag, originalLength, transformLength, transformed, sourceOffset));
      sourceOffset += transformLength;
      if (sourceOffset > 0xffffffff) {
        throw IoException(failed);
      }
    }
    return tables;
  }

  static void _readCollection(_Woff2Reader reader, int version,
      List<_Woff2Table> tables, List<_CollectionEntry> collection) {
    const failed = IoExceptionMessageConstant.readCollectionHeaderFailed;
    if (version != 0x00010000 && version != 0x00020000) {
      throw IoException(failed);
    }
    final fontCount = _read255UShort(reader, failed);
    if (fontCount == 0) throw IoException(failed);
    for (var index = 0; index < fontCount; index++) {
      final tableCount = _read255UShort(reader, failed);
      if (tableCount == 0) throw IoException(failed);
      final flavor = reader.readUint32(failed);
      final indices = <int>[];
      var glyfIndex = -1;
      var locaIndex = -1;
      for (var entry = 0; entry < tableCount; entry++) {
        final tableIndex = _read255UShort(reader, failed);
        if (tableIndex >= tables.length) throw IoException(failed);
        indices.add(tableIndex);
        if (tables[tableIndex].tag == Woff2Converter._glyfTag) {
          glyfIndex = tableIndex;
        } else if (tables[tableIndex].tag == Woff2Converter._locaTag) {
          locaIndex = tableIndex;
        }
      }
      // glyf carries loca with it, so the two must stay adjacent.
      if ((glyfIndex >= 0 || locaIndex >= 0) && locaIndex - glyfIndex != 1) {
        throw IoException(failed);
      }
      collection.add(_CollectionEntry(flavor, indices));
    }
  }

  static int _knownTag(int index) {
    final text = Woff2Converter._knownTagText;
    if (index * 4 + 4 > text.length) {
      throw IoException(IoExceptionMessageConstant.readTableDirectoryFailed);
    }
    return (text.codeUnitAt(index * 4) << 24) |
        (text.codeUnitAt(index * 4 + 1) << 16) |
        (text.codeUnitAt(index * 4 + 2) << 8) |
        text.codeUnitAt(index * 4 + 3);
  }
}

int _round4(int value) => (value + 3) & ~3;

/// Reads the variable-length unsigned integer of section 4.1.1.
///
/// All but the last byte have their top bit set, and the remaining seven bits
/// spell the number most significant group first. A leading 0x80, a sixth
/// byte, or a value that does not fit in 32 bits are all rejected: each of
/// them is a second spelling of a number that already has one, and the format
/// insists on the shortest.
int _readBase128(_Woff2Reader reader) {
  const failed = IoExceptionMessageConstant.readBase128Failed;
  var result = 0;
  for (var index = 0; index < 5; index++) {
    final code = reader.readUint8(failed);
    if (index == 0 && code == 0x80) throw IoException(failed);
    if ((result & 0xfe000000) != 0) throw IoException(failed);
    result = (result << 7) | (code & 0x7f);
    if ((code & 0x80) == 0) return result;
  }
  throw IoException(failed);
}

/// Reads the variable-length unsigned short of section 4.1.2, which spends
/// one byte on the values a font uses most and up to three on the rest.
int _read255UShort(_Woff2Reader reader, String failed) {
  final code = reader.readUint8(failed);
  switch (code) {
    case 253:
      return reader.readUint16(failed);
    case 254:
      return reader.readUint8(failed) + 253 * 2;
    case 255:
      return reader.readUint8(failed) + 253;
    default:
      return code;
  }
}

/// A cursor over a byte range that reports running off the end as the error
/// its caller names, rather than as a range check.
class _Woff2Reader {
  final Uint8List _data;
  final int _start;
  final int _end;
  int _offset;

  _Woff2Reader(Uint8List data, [int start = 0, int? end])
      : _data = data,
        _start = start,
        _end = end ?? data.length,
        _offset = start;

  int get offset => _offset - _start;

  int get remaining => _end - _offset;

  /// Rewinds to an offset already reached, which a scan that had to measure
  /// something before copying it needs.
  void seek(int position) {
    _offset = _start + position;
  }

  void skip(int count, String failed) {
    if (count < 0 || count > remaining) throw IoException(failed);
    _offset += count;
  }

  int readUint8(String failed) {
    if (remaining < 1) throw IoException(failed);
    return _data[_offset++];
  }

  int readUint16(String failed) {
    if (remaining < 2) throw IoException(failed);
    final value = (_data[_offset] << 8) | _data[_offset + 1];
    _offset += 2;
    return value;
  }

  int readInt16(String failed) {
    final value = readUint16(failed);
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  int readUint32(String failed) {
    if (remaining < 4) throw IoException(failed);
    final value = (_data[_offset] << 24) |
        (_data[_offset + 1] << 16) |
        (_data[_offset + 2] << 8) |
        _data[_offset + 3];
    _offset += 4;
    return value;
  }

  /// A view over the next [count] bytes, which stays backed by the source.
  Uint8List readBytes(int count, String failed) {
    if (count < 0 || count > remaining) throw IoException(failed);
    final view = Uint8List.sublistView(_data, _offset, _offset + count);
    _offset += count;
    return view;
  }
}

/// A growing buffer for the font being rebuilt.
///
/// The sfnt directory is written before the tables it describes, so the
/// writer has to support going back to fill an entry in; and a table's
/// checksum is the sum of the bytes as they were finally written, so it is
/// computed from this buffer rather than from anything upstream.
class _SfntWriter {
  Uint8List _bytes;
  int _length = 0;

  _SfntWriter([int capacity = 0])
      : _bytes = Uint8List(capacity < 1024 ? 1024 : capacity);

  int get length => _length;

  void _reserve(int extra) {
    if (_length + extra <= _bytes.length) return;
    var capacity = _bytes.length * 2;
    while (capacity < _length + extra) {
      capacity *= 2;
    }
    final grown = Uint8List(capacity);
    grown.setRange(0, _length, _bytes);
    _bytes = grown;
  }

  void addUint16(int value) {
    _reserve(2);
    _bytes[_length++] = (value >> 8) & 0xff;
    _bytes[_length++] = value & 0xff;
  }

  void addUint32(int value) {
    _reserve(4);
    _bytes[_length++] = (value >> 24) & 0xff;
    _bytes[_length++] = (value >> 16) & 0xff;
    _bytes[_length++] = (value >> 8) & 0xff;
    _bytes[_length++] = value & 0xff;
  }

  void addBytes(Uint8List source, int start, int end) {
    if (start < 0 || end > source.length || start > end) {
      throw IoException(IoExceptionMessageConstant.bufferReadFailed);
    }
    final count = end - start;
    _reserve(count);
    _bytes.setRange(_length, _length + count, source, start);
    _length += count;
  }

  void addZeros(int count) {
    _reserve(count);
    _length += count;
  }

  /// Pads to the four-byte boundary every sfnt table starts on.
  void padToFour() {
    addZeros(_round4(_length) - _length);
  }

  void setUint32(int offset, int value) {
    if (offset < 0 || offset + 4 > _length) {
      throw IoException(IoExceptionMessageConstant.writeFailed);
    }
    _bytes[offset] = (value >> 24) & 0xff;
    _bytes[offset + 1] = (value >> 16) & 0xff;
    _bytes[offset + 2] = (value >> 8) & 0xff;
    _bytes[offset + 3] = value & 0xff;
  }

  int getUint32(int offset) {
    if (offset < 0 || offset + 4 > _length) {
      throw IoException(IoExceptionMessageConstant.writeFailed);
    }
    return (_bytes[offset] << 24) |
        (_bytes[offset + 1] << 16) |
        (_bytes[offset + 2] << 8) |
        _bytes[offset + 3];
  }

  /// The sfnt checksum of a range: the sum of its 32-bit words, with a tail
  /// shorter than a word treated as if zeroes followed it.
  int checksum(int offset, int count) {
    if (offset < 0 || count < 0 || offset + count > _length) {
      throw IoException(IoExceptionMessageConstant.writeFailed);
    }
    var sum = 0;
    final aligned = count & ~3;
    for (var index = 0; index < aligned; index += 4) {
      sum = (sum +
              ((_bytes[offset + index] << 24) |
                  (_bytes[offset + index + 1] << 16) |
                  (_bytes[offset + index + 2] << 8) |
                  _bytes[offset + index + 3])) &
          0xffffffff;
    }
    if (aligned != count) {
      var tail = 0;
      for (var index = aligned; index < count; index++) {
        tail |= _bytes[offset + index] << (24 - 8 * (index & 3));
      }
      sum = (sum + tail) & 0xffffffff;
    }
    return sum;
  }

  /// Empties the buffer without giving up the memory it already holds, so a
  /// single instance can assemble one glyph after another.
  void reset() {
    _bytes.fillRange(0, _length, 0);
    _length = 0;
  }

  Uint8List take() => Uint8List.sublistView(_bytes, 0, _length);
}
