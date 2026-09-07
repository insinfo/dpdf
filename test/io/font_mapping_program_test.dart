import 'dart:convert';
import 'dart:typed_data';
import 'package:dpdf/src/io/font/open_type_parser.dart';
import 'package:dpdf/src/io/font/type1_font.dart';
import 'package:dpdf/src/io/font/cmap/cmap_cid_uni.dart';
import 'package:dpdf/src/io/font/cmap/cmap_uni_cid.dart';
import 'package:dpdf/src/io/font/cmap/cmap_object.dart';
import 'package:test/test.dart';

CraftOpenTypeParser grouped(List<(int, int, int)> groups) {
  final size = 16 + 12 * groups.length;
  final bytes = Uint8List(12 + size);
  final values = ByteData.sublistView(bytes);
  values.setUint32(0, 0x10000);
  values.setUint16(12, 12);
  values.setUint32(16, size);
  values.setUint32(24, groups.length);
  for (var i = 0; i < groups.length; i++) {
    final (first, last, glyph) = groups[i];
    values.setUint32(28 + i * 12, first);
    values.setUint32(32 + i * 12, last);
    values.setUint32(36 + i * 12, glyph);
  }
  return CraftOpenTypeParser(bytes)
    ..glyphWidthsByIndex = [0, 100, 200, 300, 400]
    ..tables = {
      'cmap': [12, size]
    }
    ..raf.seek(14);
}

const afm = '''StartFontMetrics 4.1
FontName Local-Test
FullName Local Test Face
FamilyName Local Family
Weight Medium
FontBBox -10 -200 900 800
ItalicAngle -12.5
IsFixedPitch false
EncodingScheme AdobeStandardEncoding
CapHeight 700
StartCharMetrics 3
CH <41> ; W0X 600 ; N A ; B 0 0 600 700 ;
C 86 ; W 650 0 ; N V ; B 0 0 650 700 ;
C 32 ; WX 250 ; N space ; B 0 0 0 0 ;
EndCharMetrics
StartKernData
StartKernPairs 1
KPX A V -80
EndKernPairs
EndKernData
EndFontMetrics
''';
CraftType1Font loadAfm(String content) =>
    CraftType1Font('', '', Uint8List.fromList(latin1.encode(content)), null);

void main() {
  test('Grouped Unicode cmap expands BMP and supplementary ranges', () {
    final parser = grouped([(65, 66, 1), (0x1f600, 0x1f601, 3)]);
    final map = parser.readGroupedUnicodeMap();
    expect(map, {
      65: [1, 100],
      66: [2, 200],
      0x1f600: [3, 300],
      0x1f601: [4, 400]
    });
    expect(parser.raf.getPosition(), parser.raf.length());
  });
  test(
      'Grouped cmap validates Unicode ordering and glyph limits before expansion',
      () {
    for (final rows in <List<(int, int, int)>>[
      [(66, 65, 1)],
      [(65, 66, 1), (66, 67, 2)],
      [(0x110000, 0x110000, 1)],
      [(0xd800, 0xd800, 1)],
      [(65, 70, 1)],
    ]) {
      expect(grouped(rows).readGroupedUnicodeMap, throwsFormatException);
    }
  });
  test('Grouped cmap cannot borrow bytes beyond its declared parent table', () {
    final parser = grouped([(65, 65, 1)]);
    parser.tables['cmap']![1] = 16;
    expect(parser.readGroupedUnicodeMap, throwsFormatException);
    final missing = grouped([(65, 65, 1)]);
    ByteData.sublistView(missing.raf.getBytes()).setUint32(24, 2);
    expect(missing.readGroupedUnicodeMap, throwsFormatException);
  });
  test('CID directions preserve supplementary scalars', () {
    final source = String.fromCharCodes([0xd8, 0x3d, 0xde, 0]);
    final destination = CraftCMapObject(CraftCMapObject.number, 42);
    final toUnicode = CraftCMapCidUni()
      ..registerMappedCode(source, destination);
    final toCid = CraftCMapUniCid()..registerMappedCode(source, destination);
    expect(toUnicode.lookup(42), 0x1f600);
    expect(toCid.lookup(0x1f600), 42);
    expect(toCid.exportToUnicode().lookupInt(42), '😀');
  });
  test('CID directions reject multi-scalar and broken UTF16 values', () {
    for (final source in [
      '',
      'A',
      String.fromCharCodes([0, 65, 0, 66]),
      String.fromCharCodes([0xd8, 0, 0, 65]),
      String.fromCharCodes([0xdc, 0])
    ]) {
      final code = CraftCMapObject(CraftCMapObject.number, 1);
      expect(() => CraftCMapCidUni().registerMappedCode(source, code),
          throwsFormatException);
      expect(() => CraftCMapUniCid().registerMappedCode(source, code),
          throwsFormatException);
    }
  });
  test('AFM record parser preserves multiword metadata and hex character codes',
      () {
    final font = loadAfm(afm);
    expect(font.getFontNames().getFontName(), 'Local-Test');
    expect(font.getFontMetrics().getBbox(), [-10, -200, 900, 800]);
    expect(font.getFontMetrics().getItalicAngle(), -12.5);
    expect(font.getGlyph(65)!.getCode(), 65);
    expect(font.getGlyph(65)!.getWidth(), 600);
    expect(font.getGlyph(86)!.getWidth(), 650);
    expect(font.getGlyph(160)!.getWidth(), 250);
    expect(font.getKerning(65, 86), -80);
    expect(font.getIsFontSpecific(), isFalse);
  });
  test('AFM section state rejects truncation and incorrect record counts', () {
    for (final data in [
      afm.replaceFirst('StartCharMetrics 3', 'StartCharMetrics 2'),
      afm.replaceFirst('EndCharMetrics', ''),
      afm.replaceFirst('StartKernPairs 1', 'StartKernPairs 2'),
      afm.replaceFirst('EndFontMetrics', '')
    ]) {
      expect(() => loadAfm(data), throwsFormatException);
    }
  });
}
