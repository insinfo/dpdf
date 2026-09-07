import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/io/font/cmap/cmap_to_unicode.dart';
import 'package:dpdf/src/io/font/cmap/cmap_object.dart';

void main() {
  test('all code widths and sliced defaults use unsigned codes', () {
    final map = CMapToUnicode();
    for (final bytes in [
      [42],
      [1, 42],
      [1, 2, 42],
      [255, 2, 3, 42]
    ]) {
      map.registerMappedCode(String.fromCharCodes(bytes),
          CMapObject(CMapObject.hexString, [0, 65]));
      expect(map.lookup(Uint8List.fromList([99, ...bytes]), 1), 'A');
    }
    expect(() => map.lookup(Uint8List(2), -1), throwsRangeError);
    expect(() => map.lookup(Uint8List(2), 1, 2), throwsRangeError);
    expect(() => map.lookup(Uint8List(5)), throwsRangeError);
  });
  test('scalar mappings include supplementary but omit sequences', () {
    final map = CMapToUnicode();
    map.registerMappedCode(
        'a', CMapObject(CMapObject.hexString, [0xd8, 0x3d, 0xde, 0x00]));
    map.addCharInt(98, 'fi');
    expect(map.lookupInt(97), '😀');
    expect(map.createDirectMapping().get(97), 0x1f600);
    expect(map.createReverseMapping(), {0x1f600: 97});
  });
  test('identity contains exactly the two-byte code domain', () {
    final map = CMapToUnicode.getIdentity();
    expect(map.getCodes().length, 65536);
    expect(map.lookupInt(65535), '\uffff');
    expect(map.lookupInt(65536), isNull);
  });
  test('malformed Unicode and non-byte source codes fail', () {
    final map = CMapToUnicode();
    for (final bytes in [
      [0],
      [0xd8, 0],
      [0xdc, 0],
      [0xd8, 0, 0, 65]
    ]) {
      expect(
          () => map.registerMappedCode(
              'a', CMapObject(CMapObject.hexString, bytes)),
          throwsFormatException);
    }
    expect(() => map.registerMappedCode('Ā', CMapObject(CMapObject.number, 65)),
        throwsArgumentError);
    expect(() => map.addCharInt(1, '\ud800'), throwsFormatException);
    expect(() => map.addCharInt(-1, 'a'), throwsRangeError);
    expect(map.hasByteMappings(), isFalse);
  });
  test('literal UTF16 and legacy odd PDFDocEncoding are retained', () {
    final map = CMapToUnicode();
    map.registerMappedCode('a', CMapObject(CMapObject.string, [0, 65]));
    map.registerMappedCode('b', CMapObject(CMapObject.string, [65]));
    expect(map.lookupInt(97), 'A');
    expect(map.lookupInt(98), 'A');
  });
  test('ranges validate widths ordering and own their buffers', () {
    final map = CMapToUnicode();
    expect(
        () => map.registerCodeInterval(
            Uint8List.fromList([1, 255]), Uint8List.fromList([2, 0])),
        throwsArgumentError);
    expect(() => map.registerCodeInterval(Uint8List(0), Uint8List(0)),
        throwsArgumentError);
    expect(() => map.registerCodeInterval(Uint8List(5), Uint8List(5)),
        throwsArgumentError);
    final low = Uint8List.fromList([0]), high = Uint8List.fromList([255]);
    map.registerCodeInterval(low, high);
    low[0] = 1;
    map.getCodeSpaceRanges()[1][0] = 1;
    expect(map.getCodeSpaceRanges(), [
      [0],
      [255]
    ]);
    expect(() => map.registerCodeInterval(high, low), throwsArgumentError);
    expect(
        () => map.registerCodeInterval(low, Uint8List(2)), throwsArgumentError);
  });
}
