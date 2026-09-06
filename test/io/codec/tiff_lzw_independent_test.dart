import 'dart:typed_data';
import 'package:pdfcraft/src/io/codec/lzw_compressor.dart';
import 'package:pdfcraft/src/io/codec/tiff_lzw_decoder.dart';
import 'package:pdfcraft/src/io/exceptions/io_exception.dart';
import 'package:test/test.dart';

Uint8List fixedNineBitCodes(List<int> codes) {
  final bits =
      codes.map((code) => code.toRadixString(2).padLeft(9, '0')).join();
  final padded = bits.padRight(((bits.length + 7) ~/ 8) * 8, '0');
  return Uint8List.fromList([
    for (var index = 0; index < padded.length; index += 8)
      int.parse(padded.substring(index, index + 8), radix: 2),
  ]);
}

void main() {
  test('literal codes and reset inside a strip', () {
    final decoder = CraftTIFFLZWDecoder(4, 1, 1);
    final bytes = fixedNineBitCodes([256, 65, 66, 256, 67, 68, 257]);
    expect(decoder.decode(bytes, Uint8List(4), 1), [65, 66, 67, 68]);
    expect(decoder.decode(bytes, Uint8List(4), 1), [65, 66, 67, 68]);
  });
  test('next dictionary entry may refer to the word being created', () {
    final bytes = fixedNineBitCodes([256, 65, 258, 259, 257]);
    expect(CraftLZWDecoder.decode(bytes, expectedSize: 6), List.filled(6, 65));
  });
  test('RGB predictor restarts at each row', () {
    final bytes =
        fixedNineBitCodes([256, 10, 20, 30, 2, 3, 4, 50, 60, 70, 1, 2, 3, 257]);
    expect(
        CraftLZWDecoder.decode(bytes,
            expectedSize: 12,
            width: 2,
            height: 2,
            samplesPerPixel: 3,
            predictor: 2),
        [10, 20, 30, 12, 23, 34, 50, 60, 70, 51, 62, 73]);
  });
  test('rejects undefined dictionary references', () {
    expect(
        () => CraftLZWDecoder.decode(fixedNineBitCodes([256, 65, 300]),
            expectedSize: 20),
        throwsA(isA<IoException>()));
  });
  test('truncated strip retains bounded legacy output behavior', () {
    expect(
        CraftLZWDecoder.decode(fixedNineBitCodes([256, 65]), expectedSize: 3),
        [65, 0, 0]);
    expect(
        CraftLZWDecoder.decode(fixedNineBitCodes([256, 65, 258]),
            expectedSize: 2),
        [65, 65]);
  });
  test('code-width changes and dictionary resets on a large strip', () {
    var state = 0x12345678;
    final input = Uint8List.fromList(List.generate(100000, (_) {
      state ^= state << 13;
      state ^= state >>> 17;
      state ^= state << 5;
      state &= 0xffffffff;
      return state & 255;
    }));
    final compressed = LZWEncoder.compress(input);
    expect(
        CraftLZWDecoder.decode(compressed, expectedSize: input.length), input);
  });
}
