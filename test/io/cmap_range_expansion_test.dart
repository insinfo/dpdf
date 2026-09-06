import 'dart:typed_data';
import 'package:pdfcraft/src/io/font/cmap/abstract_cmap.dart';
import 'package:pdfcraft/src/io/font/cmap/cmap_object.dart';
import 'package:test/test.dart';

class _RecordedMap extends CraftAbstractCMap {
  final entries = <String, CraftCMapObject>{};
  @override
  void registerMappedCode(String mark, CraftCMapObject code) =>
      entries[mark] = code;
}

String _bytes(List<int> values) => String.fromCharCodes(values);

void main() {
  test('byte helpers preserve truncation, signed extension and empty buffers',
      () {
    expect(CraftAbstractCMap.mappingCodeBytes('\u0101\u00ff'), [1, 255]);
    final bytes = Uint8List(10);
    CraftAbstractCMap.writeMappingInteger(-2, bytes);
    expect(bytes, [...List.filled(9, 255), 254]);
    CraftAbstractCMap.writeMappingInteger(0x123456, bytes);
    expect(bytes, [...List.filled(7, 0), 0x12, 0x34, 0x56]);
    expect(CraftAbstractCMap.readMappingInteger(bytes), 0x123456);
    final short = Uint8List(2);
    CraftAbstractCMap.writeMappingInteger(0x123456, short);
    expect(short, [0x34, 0x56]);
    CraftAbstractCMap.writeMappingInteger(1, Uint8List(0));
    expect(CraftAbstractCMap.readMappingInteger(Uint8List(0)), 0);
  });

  test('text decoding chooses UTF16 by syntax or marker and PDFDoc otherwise',
      () {
    final map = _RecordedMap();
    expect(map.decodeMappingText(_bytes([0, 65, 0, 66]), true), 'AB');
    expect(map.decodeMappingText(_bytes([254, 255, 0, 65]), false), 'A');
    expect(map.decodeMappingText('ABC', false), 'ABC');
    expect(map.decodeMappingText('', false), '');
  });

  test('range advances source codes across a byte boundary', () {
    final map = _RecordedMap();
    map.expandMappingInterval(_bytes([0, 254]), _bytes([1, 1]),
        CraftCMapObject(CraftCMapObject.number, 30));
    expect(map.entries.keys.map((key) => key.codeUnits), [
      [0, 254],
      [0, 255],
      [1, 0],
      [1, 1]
    ]);
    expect(
        map.entries.values.map((value) => value.getValue()), [30, 31, 32, 33]);
  });

  test('text increment retains bytes beyond machine integer precision', () {
    final map = _RecordedMap();
    final original = Uint8List.fromList([0, 65, 0, 66, 0, 67, 0, 68, 0, 255]);
    map.expandMappingInterval(
        'a', 'b', CraftCMapObject(CraftCMapObject.hexString, original));
    expect(map.entries['a']!.getValue(), original);
    expect(map.entries['b']!.getValue(), [0, 65, 0, 66, 0, 67, 0, 68, 1, 0]);
    expect(original, [0, 65, 0, 66, 0, 67, 0, 68, 0, 255]);
    expect(identical(map.entries['a']!.getValue(), original), isFalse);
  });

  test('array destinations preserve order and are checked before changes', () {
    final map = _RecordedMap();
    final values = [CraftCMapObject(CraftCMapObject.number, 9)];
    expect(
        () => map.expandMappingInterval(
            'a', 'b', CraftCMapObject(CraftCMapObject.array, values)),
        throwsArgumentError);
    expect(map.entries, isEmpty);
    values.add(CraftCMapObject(CraftCMapObject.number, 2));
    map.expandMappingInterval(
        'a', 'b', CraftCMapObject(CraftCMapObject.array, values));
    expect(map.entries.values.map((value) => value.getValue()), [9, 2]);
  });

  test('invalid interval and destination forms leave map untouched', () {
    final map = _RecordedMap();
    final numeric = CraftCMapObject(CraftCMapObject.number, 1);
    for (final pair in [
      ['', ''],
      ['a', 'bb'],
      ['b', 'a'],
      ['Ā', 'ā']
    ]) {
      expect(() => map.expandMappingInterval(pair[0], pair[1], numeric),
          throwsArgumentError);
    }
    expect(
        () => map.expandMappingInterval(
            'a', 'a', CraftCMapObject(CraftCMapObject.hexString, Uint8List(0))),
        throwsArgumentError);
    expect(
        () => map.expandMappingInterval(
            'a', 'a', CraftCMapObject(CraftCMapObject.name, 'Unsupported')),
        throwsArgumentError);
    expect(map.entries, isEmpty);
  });
}
