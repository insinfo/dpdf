import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/src/io/font/base_encodings.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:test/test.dart';

/// Assembles an sfnt font from the tables it is given, in tag order and on
/// four-byte boundaries, exactly as ISO 32000-1:2008, 9.9 expects to find
/// an embedded TrueType program.
Uint8List buildSfnt(Map<String, List<int>> tables) {
  final tags = tables.keys.toList()..sort();
  var offset = 12 + tags.length * 16;
  final directory = ByteData(12 + tags.length * 16);
  directory.setUint32(0, 0x00010000);
  directory.setUint16(4, tags.length);
  final body = <int>[];
  for (var index = 0; index < tags.length; index++) {
    final data = tables[tags[index]]!;
    final entry = 12 + index * 16;
    directory.setUint32(
        entry,
        ByteData.sublistView(Uint8List.fromList(tags[index].codeUnits))
            .getUint32(0));
    directory.setUint32(entry + 8, offset);
    directory.setUint32(entry + 12, data.length);
    body.addAll(data);
    offset += data.length;
    while (offset % 4 != 0) {
      body.add(0);
      offset++;
    }
  }
  return Uint8List.fromList([...directory.buffer.asUint8List(), ...body]);
}

List<int> _head(int unitsPerEm) {
  final table = ByteData(54);
  table.setUint32(0, 0x00010000);
  table.setUint16(18, unitsPerEm);
  table.setInt16(36, 0); // xMin
  table.setInt16(38, -200); // yMin
  table.setInt16(40, 1000); // xMax
  table.setInt16(42, 800); // yMax
  table.setUint16(50, 0); // indexToLocFormat
  return table.buffer.asUint8List();
}

List<int> _hhea(int metricCount) {
  final table = ByteData(36);
  table.setUint32(0, 0x00010000);
  table.setInt16(4, 800); // ascender
  table.setInt16(6, -200); // descender
  table.setUint16(34, metricCount);
  return table.buffer.asUint8List();
}

List<int> _maxp(int glyphCount) {
  final table = ByteData(32);
  table.setUint32(0, 0x00010000);
  table.setUint16(4, glyphCount);
  return table.buffer.asUint8List();
}

List<int> _hmtx(List<int> advances) {
  final table = ByteData(advances.length * 4);
  for (var glyph = 0; glyph < advances.length; glyph++) {
    table.setUint16(glyph * 4, advances[glyph]);
  }
  return table.buffer.asUint8List();
}

/// One contiguous run of character codes, in the "cmap" subtable format
/// that every platform understands.
List<int> _format4(int first, int last, int firstGlyph) {
  const segments = 2;
  final table = ByteData(16 + segments * 8);
  table.setUint16(0, 4);
  table.setUint16(2, table.lengthInBytes);
  table.setUint16(6, segments * 2);
  table.setUint16(14, first); // endCode[0]
  table.setUint16(16, 0xffff); // endCode[1]
  table.setUint16(18, 0); // reservedPad
  table.setUint16(20, first); // startCode[0]
  table.setUint16(22, 0xffff);
  table.setUint16(24, (firstGlyph - first) & 0xffff); // idDelta[0]
  table.setUint16(26, 1);
  table.setUint16(28, 0); // idRangeOffset[0]
  table.setUint16(30, 0);
  // The single segment covers the whole run.
  table.setUint16(14, last);
  return table.buffer.asUint8List();
}

List<int> _cmap(List<(int, int, List<int>)> subtables) {
  var offset = 4 + subtables.length * 8;
  final header = ByteData(offset);
  header.setUint16(2, subtables.length);
  final body = <int>[];
  for (var index = 0; index < subtables.length; index++) {
    final (platform, encoding, data) = subtables[index];
    header.setUint16(4 + index * 8, platform);
    header.setUint16(6 + index * 8, encoding);
    header.setUint32(8 + index * 8, offset);
    body.addAll(data);
    offset += data.length;
  }
  return [...header.buffer.asUint8List(), ...body];
}

/// A "post" table of version 2.0, which spells out the names of the glyphs
/// that the standard Macintosh ordering does not already cover.
List<int> _post(List<String> names) {
  final header = ByteData(34 + names.length * 2);
  header.setUint32(0, 0x00020000);
  header.setUint16(32, names.length);
  final custom = <String>[];
  for (var glyph = 0; glyph < names.length; glyph++) {
    final standard = BaseEncodings.macGlyphOrder.indexOf(names[glyph]);
    if (standard >= 0) {
      header.setUint16(34 + glyph * 2, standard);
    } else {
      header.setUint16(34 + glyph * 2, 258 + custom.length);
      custom.add(names[glyph]);
    }
  }
  return [
    ...header.buffer.asUint8List(),
    for (final name in custom) ...[name.length, ...name.codeUnits],
  ];
}

void main() {
  group('a font that offers only a (3, 0) subtable', () {
    // The guideline of 9.6.6.4: a symbolic font maps its codes through the
    // 0xF000 page, and the reader prepends the high byte of the range.
    final font = TrueTypeFont.fromBytes(buildSfnt({
      'head': _head(1000),
      'hhea': _hhea(4),
      'maxp': _maxp(4),
      'hmtx': _hmtx([0, 500, 600, 700]),
      'cmap': _cmap([(3, 0, _format4(0xf041, 0xf043, 1))]),
    }));

    test('single bytes reach the glyphs through the high byte', () {
      expect(font.getGlyphBySymbolicCode(0x41)!.getCode(), 1);
      expect(font.getGlyphBySymbolicCode(0x42)!.getCode(), 2);
      expect(font.getGlyphBySymbolicCode(0x43)!.getCode(), 3);
      expect(font.getGlyphBySymbolicCode(0x44), isNull);
      expect(font.getGlyphBySymbolicCode(0x100), isNull);
      expect(font.getGlyphBySymbolicCode(-1), isNull);
    });

    test('the advance width comes from the glyph the code reaches', () {
      expect(font.getGlyphBySymbolicCode(0x42)!.getWidth(), 600);
    });

    test('the font reports itself as symbolic', () {
      expect(font.getIsFontSpecific(), isTrue);
    });
  });

  test('a (3, 0) subtable in the unshifted range is read as it stands', () {
    final font = TrueTypeFont.fromBytes(buildSfnt({
      'head': _head(1000),
      'hhea': _hhea(3),
      'maxp': _maxp(3),
      'hmtx': _hmtx([0, 500, 600]),
      'cmap': _cmap([(3, 0, _format4(0x0020, 0x0021, 1))]),
    }));
    expect(font.getGlyphBySymbolicCode(0x20)!.getCode(), 1);
    expect(font.getGlyphBySymbolicCode(0x21)!.getCode(), 2);
  });

  test('a (3, 0) subtable in the 0xF200 range is reached as well', () {
    final font = TrueTypeFont.fromBytes(buildSfnt({
      'head': _head(1000),
      'hhea': _hhea(3),
      'maxp': _maxp(3),
      'hmtx': _hmtx([0, 500, 600]),
      'cmap': _cmap([(3, 0, _format4(0xf230, 0xf231, 1))]),
    }));
    expect(font.getGlyphBySymbolicCode(0x30)!.getCode(), 1);
    expect(font.getGlyphBySymbolicCode(0x31)!.getCode(), 2);
  });

  group('a font that offers only a (1, 0) subtable', () {
    final font = TrueTypeFont.fromBytes(buildSfnt({
      'head': _head(1000),
      'hhea': _hhea(4),
      'maxp': _maxp(4),
      'hmtx': _hmtx([0, 500, 600, 700]),
      // Mac OS Roman codes: 0x80 Adieresis, 0x81 Aring, 0x82 Ccedilla.
      'cmap': _cmap([(1, 0, _format4(0x80, 0x82, 1))]),
    }));

    test('a symbolic byte reaches the subtable unchanged', () {
      expect(font.getGlyphBySymbolicCode(0x80)!.getCode(), 1);
      expect(font.getGlyphBySymbolicCode(0x7f), isNull);
    });

    test('a glyph name reaches it through Mac OS Roman', () {
      expect(font.getGlyphByName('Adieresis')!.getCode(), 1);
      expect(font.getGlyphByName('Aring')!.getCode(), 2);
      expect(font.getGlyphByName('Ccedilla')!.getCode(), 3);
      expect(font.getGlyphByName('A'), isNull,
          reason: 'code 0x41 is outside the subtable');
    });
  });

  group('a font with a (3, 1) subtable and named glyphs', () {
    final font = TrueTypeFont.fromBytes(buildSfnt({
      'head': _head(1000),
      'hhea': _hhea(4),
      'maxp': _maxp(4),
      'hmtx': _hmtx([0, 500, 600, 700]),
      'cmap': _cmap([(3, 1, _format4(0x41, 0x42, 1))]),
      'post': _post(['.notdef', 'A', 'B', 'uniE000']),
    }));

    test('a name is carried to Unicode and then to the subtable', () {
      expect(font.getGlyphByName('A')!.getCode(), 1);
      expect(font.getGlyphByName('A')!.getUnicode(), 0x41);
      expect(font.getGlyphByName('B')!.getCode(), 2);
    });

    test('what the subtable misses is looked up in the post table', () {
      final glyph = font.getGlyphByName('uniE000');
      expect(glyph, isNotNull);
      expect(glyph!.getCode(), 3);
      expect(glyph.getWidth(), 700);
      expect(font.getGlyphByName('nonesuch'), isNull);
    });

    test('the post table names every glyph it declares', () {
      expect(font.fontParser.readPostGlyphNames(),
          ['.notdef', 'A', 'B', 'uniE000']);
      expect(font.fontParser.postGlyphIndex('B'), 2);
      expect(font.fontParser.postGlyphIndex('nonesuch'), isNull);
    });
  });

  test('a font without a post table simply offers no names', () {
    final font = TrueTypeFont.fromBytes(buildSfnt({
      'head': _head(1000),
      'hhea': _hhea(2),
      'maxp': _maxp(2),
      'hmtx': _hmtx([0, 500]),
      'cmap': _cmap([(3, 1, _format4(0x41, 0x41, 1))]),
    }));
    expect(font.fontParser.readPostGlyphNames(), isEmpty);
    expect(font.getGlyphByName('A')!.getCode(), 1);
    expect(font.getGlyphByName('B'), isNull);
  });

  test('a real font resolves its names through all three routes', () {
    final font = TrueTypeFont.fromBytes(
        File('test/assets/ABeeZee-Regular.ttf').readAsBytesSync());
    // ABeeZee carries a (3, 1) subtable and a version 2.0 "post" table.
    expect(font.getGlyphByName('A')!.getCode(), font.getGlyph(0x41)!.getCode());
    expect(font.getGlyphByName('Adieresis')!.getCode(),
        font.getGlyph(0xc4)!.getCode());
    expect(
        font.getGlyphByName('space')!.getCode(), font.getGlyph(32)!.getCode());
    expect(font.getGlyphByName('nonesuch'), isNull);
    final names = font.fontParser.readPostGlyphNames();
    expect(names.first, '.notdef');
    expect(names.length, greaterThan(200));
    expect(font.fontParser.postGlyphIndex('A'), font.getGlyph(0x41)!.getCode());
    // The same table is only parsed once, however often it is consulted.
    expect(identical(names, font.fontParser.readPostGlyphNames()), isTrue);
  });
}
