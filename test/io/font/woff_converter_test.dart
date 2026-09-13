import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/src/commons/exceptions/dpdf_exception.dart';
import 'package:dpdf/src/io/font/font_program_factory.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/io/font/woff_converter.dart';
import 'package:dpdf/src/platform/compression.dart';
import 'package:test/test.dart';

/// Wraps an sfnt font as a WOFF 1.0 file, which is what a web font tool
/// does: the table data is copied verbatim, deflated when that saves space,
/// and described by a directory that also records the original length.
///
/// Building the fixture here rather than shipping one keeps the test honest
/// about what the format is, and lets it check the decoder against the very
/// font the wrapper was built from.
Uint8List buildWoff(Uint8List sfnt, {bool compress = true}) {
  final source = ByteData.sublistView(sfnt);
  final tableCount = source.getUint16(4);
  final tables = <(int, Uint8List, int)>[];
  for (var index = 0; index < tableCount; index++) {
    final entry = 12 + index * 16;
    final tag = source.getUint32(entry);
    final checksum = source.getUint32(entry + 4);
    final offset = source.getUint32(entry + 8);
    final length = source.getUint32(entry + 12);
    tables.add(
        (tag, Uint8List.sublistView(sfnt, offset, offset + length), checksum));
  }

  var sfntSize = 12 + tableCount * 16;
  final payloads = <Uint8List>[];
  for (final (_, data, __) in tables) {
    sfntSize += (data.length + 3) & ~3;
    final deflated = Uint8List.fromList(ZLibEncoder().convert(data));
    payloads.add(compress && deflated.length < data.length ? deflated : data);
  }

  var cursor = 44 + tableCount * 20;
  final body = <int>[];
  final directory = ByteData(tableCount * 20);
  for (var index = 0; index < tableCount; index++) {
    final (tag, data, checksum) = tables[index];
    final payload = payloads[index];
    directory.setUint32(index * 20, tag);
    directory.setUint32(index * 20 + 4, cursor);
    directory.setUint32(index * 20 + 8, payload.length);
    directory.setUint32(index * 20 + 12, data.length);
    directory.setUint32(index * 20 + 16, checksum);
    body.addAll(payload);
    cursor += payload.length;
    // Every table but the last begins on a four-byte boundary.
    while (index < tableCount - 1 && cursor % 4 != 0) {
      body.add(0);
      cursor++;
    }
  }

  final header = ByteData(44);
  header.setUint32(0, 0x774f4646);
  header.setUint32(4, source.getUint32(0));
  header.setUint32(8, 44 + tableCount * 20 + body.length);
  header.setUint16(12, tableCount);
  header.setUint32(16, sfntSize);
  header.setUint16(20, 1); // majorVersion
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...directory.buffer.asUint8List(),
    ...body,
  ]);
}

void main() {
  final sfnt = File('test/assets/ABeeZee-Regular.ttf').readAsBytesSync();

  test('a WOFF file is recognised by its signature alone', () {
    expect(WoffConverter.isWoff(buildWoff(sfnt)), isTrue);
    expect(WoffConverter.isWoff(sfnt), isFalse);
    expect(WoffConverter.isWoff2(sfnt), isFalse);
    expect(WoffConverter.isWoff(const []), isFalse);
    expect(WoffConverter.isWoff2([0x77, 0x4f, 0x46, 0x32]), isTrue);
  });

  test('decoding restores every table of the original font', () {
    final restored = WoffConverter.convert(buildWoff(sfnt));
    final original = ByteData.sublistView(sfnt);
    final rebuilt = ByteData.sublistView(restored);
    final tableCount = original.getUint16(4);
    expect(rebuilt.getUint32(0), original.getUint32(0), reason: 'flavour');
    expect(rebuilt.getUint16(4), tableCount);

    for (var index = 0; index < tableCount; index++) {
      final source = 12 + index * 16;
      final tag = original.getUint32(source);
      final offset = original.getUint32(source + 8);
      final length = original.getUint32(source + 12);
      final target = 12 + index * 16;
      expect(rebuilt.getUint32(target), tag, reason: 'table $index tag');
      expect(rebuilt.getUint32(target + 4), original.getUint32(source + 4),
          reason: 'table $index checksum');
      expect(rebuilt.getUint32(target + 12), length,
          reason: 'table $index length');
      final restoredOffset = rebuilt.getUint32(target + 8);
      expect(
          Uint8List.sublistView(
              restored, restoredOffset, restoredOffset + length),
          Uint8List.sublistView(sfnt, offset, offset + length),
          reason: 'table $index data');
    }
  });

  test('uncompressed tables are copied through unchanged', () {
    final restored = WoffConverter.convert(buildWoff(sfnt, compress: false));
    final compressed = WoffConverter.convert(buildWoff(sfnt));
    expect(restored, compressed);
  });

  test('the restored font parses into the same program', () {
    final direct = TrueTypeFont.fromBytes(sfnt);
    final unwrapped =
        FontProgramFactory.createFontFromBytes(buildWoff(sfnt), false);
    expect(unwrapped, isA<TrueTypeFont>());
    final woffFont = unwrapped as TrueTypeFont;
    expect(woffFont.getFontNames().getFontName(),
        direct.getFontNames().getFontName());
    expect(woffFont.countOfGlyphs(), direct.countOfGlyphs());
    expect(woffFont.getWidth(0x41), direct.getWidth(0x41));
    expect(
        woffFont.getGlyph(0x41)!.getCode(), direct.getGlyph(0x41)!.getCode());
    expect(
        woffFont.getFontMetrics().getBbox(), direct.getFontMetrics().getBbox());
  });

  test('a font that is not wrapped passes through toSfnt untouched', () {
    expect(identical(WoffConverter.toSfnt(sfnt), sfnt), isTrue);
    expect(WoffConverter.toSfnt(buildWoff(sfnt)).sublist(0, 4),
        sfnt.sublist(0, 4));
  });

  test('WOFF 2.0 is reported rather than misread as sfnt', () {
    final woff2 = Uint8List.fromList([0x77, 0x4f, 0x46, 0x32, ...sfnt]);
    expect(() => WoffConverter.toSfnt(woff2), throwsA(isA<DpdfException>()));
  });

  group('damaged files are rejected', () {
    test('a truncated header', () {
      expect(() => WoffConverter.convert(Uint8List(20)),
          throwsA(isA<DpdfException>()));
    });

    test('a declared length that is not the file length', () {
      final woff = buildWoff(sfnt);
      ByteData.sublistView(woff).setUint32(8, woff.length - 1);
      expect(() => WoffConverter.convert(woff), throwsA(isA<DpdfException>()));
    });

    test('a declared sfnt size that the tables do not add up to', () {
      final woff = buildWoff(sfnt);
      ByteData.sublistView(woff).setUint32(16, 17);
      expect(() => WoffConverter.convert(woff), throwsA(isA<DpdfException>()));
    });

    test('a table directory that is out of tag order', () {
      final woff = buildWoff(sfnt);
      final view = ByteData.sublistView(woff);
      final first = view.getUint32(44);
      view.setUint32(44, view.getUint32(64));
      view.setUint32(64, first);
      expect(() => WoffConverter.convert(woff), throwsA(isA<DpdfException>()));
    });

    test('a table that reaches past the end of the file', () {
      final woff = buildWoff(sfnt);
      ByteData.sublistView(woff).setUint32(48, woff.length);
      expect(() => WoffConverter.convert(woff), throwsA(isA<DpdfException>()));
    });

    test('a table whose compressed data is corrupt', () {
      final woff = buildWoff(sfnt);
      final view = ByteData.sublistView(woff);
      // Find a table the fixture actually deflated, then damage its payload.
      for (var index = 0; index < view.getUint16(12); index++) {
        final entry = 44 + index * 20;
        final compressed = view.getUint32(entry + 8);
        if (compressed == view.getUint32(entry + 12)) continue;
        woff[view.getUint32(entry + 4) + compressed ~/ 2] ^= 0xff;
        expect(
            () => WoffConverter.convert(woff), throwsA(isA<DpdfException>()));
        return;
      }
      fail('the fixture compressed no table');
    });
  });
}
