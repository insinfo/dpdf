import 'dart:typed_data';
import 'dart:convert';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/font/unicode_code_map.dart';
import 'package:dpdf/src/io/font/cmap/cmap_object.dart';
import 'package:test/test.dart';

void main() {
  test('Existing CMap parser integrates with the replacement storage',
      () async {
    final stream = PdfStream.withBytes(Uint8List.fromList(ascii.encode('''
begincmap
1 begincodespacerange <00> <FF> endcodespacerange
2 beginbfchar <01> <00660069> <02> <D83DDE00> endbfchar
1 beginbfrange <03> <05> <0041> endbfrange
endcmap
''')), 0);
    final map = await UnicodeCodeMap.fromStream(stream);
    expect(map.textForCode(1), 'fi');
    expect(map.textForCode(2), '😀');
    expect([map.textForCode(3), map.textForCode(4), map.textForCode(5)],
        ['A', 'B', 'C']);
  });
  test('Replacing mappings cannot retain stale scalar or sequence entries', () {
    final map = UnicodeCodeMap();
    map.setMapping(42, 'fi');
    map.setScalar(42, 65);
    expect(map.textForCode(42), 'A');
    expect(map.hasSequence(42), isFalse);
    expect(map.codeForText('fi'), isNull);
    map.setMapping(42, 'ffi');
    expect(map.codeForScalar(65), isNull);
    expect(map.codeForText('ffi'), 42);
    map.setMapping(42, '');
    expect(map.textForCode(42), '');
    expect(map.hasSequence(42), isFalse);
  });

  test('UTF16BE and reverse lookup include supplementary Unicode', () {
    final map = UnicodeCodeMap();
    map.registerMappedCode(
        String.fromCharCodes([1, 2, 3]),
        CMapObject(CMapObject.hexString,
            Uint8List.fromList([0xd8, 0x3d, 0xde, 0x00])));
    expect(map.textForCode(0x010203), '😀');
    expect(map.codeForScalar(0x1f600), 0x010203);
    map.registerMappedCode(
        'B',
        CMapObject(CMapObject.hexString,
            Uint8List.fromList([0xfe, 0xff, 0x00, 0xe7])));
    expect(map.textForCode(66), 'ç');
    map.registerMappedCode('C', CMapObject(CMapObject.string, '\x00A'));
    expect(map.decodeCodes('BC'.codeUnits), 'çA');
  });

  test('Invalid updates fail without destroying the prior mapping', () {
    final map = UnicodeCodeMap()..setScalar(1, 65);
    expect(() => map.setMapping(1, String.fromCharCode(0xd800)),
        throwsFormatException);
    expect(map.textForCode(1), 'A');
    expect(() => map.setScalar(1, 0xd800), throwsRangeError);
    expect(
        () => map.registerMappedCode(
            'A', CMapObject(CMapObject.hexString, Uint8List.fromList([65]))),
        throwsFormatException);
    expect(() => map.registerMappedCode('', CMapObject(CMapObject.number, 65)),
        throwsFormatException);
  });
}
