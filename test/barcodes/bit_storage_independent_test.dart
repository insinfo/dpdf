import 'package:test/test.dart';
import 'package:dpdf/src/barcodes/qrcode/bit_array.dart';
import 'package:dpdf/src/barcodes/qrcode/bit_matrix.dart';
import 'package:dpdf/src/barcodes/qrcode/bit_vector.dart';

void main() {
  test('fixed bits preserve word layout and reverse odd lengths', () {
    for (final size in [1, 7, 8, 31, 32, 33, 63, 65]) {
      final bits = BitArray(size);
      final marked = <int>{0, size ~/ 2, size - 1};
      for (final i in marked) {
        bits.set(i);
      }
      final old = bits.getBitArray();
      bits.reverse();
      for (var i = 0; i < size; i++) {
        expect(bits.get(i), marked.contains(size - i - 1));
      }
      expect(identical(old, bits.getBitArray()), isFalse);
      bits.clear();
      expect(bits.isRange(0, size, false), isTrue);
      expect(bits.isRange(size, size, true), isTrue);
      expect(() => bits.get(size), throwsRangeError);
      expect(() => bits.isRange(-1, 0, false), throwsRangeError);
    }
  });
  test(
      'signed words match full 32-bit ranges and bulk addresses containing word',
      () {
    final bits = BitArray(65)
      ..setBulk(3, -1)
      ..setBulk(32, -1);
    expect(bits.isRange(0, 64, true), isTrue);
    expect(bits.get(64), isFalse);
    bits.getBitArray()[0] = 1;
    expect(bits.get(0), isTrue);
    expect(bits.get(1), isFalse);
  });
  test('matrix regions cross word boundaries with reusable row buffers', () {
    final matrix = BitMatrix(35, 3)..setRegion(30, 1, 5, 2);
    final buffer = BitArray(96)
      ..set(63)
      ..set(80);
    expect(identical(matrix.getRow(1, buffer), buffer), isTrue);
    expect(buffer.isRange(0, 30, false), isTrue);
    expect(buffer.isRange(30, 35, true), isTrue);
    expect(buffer.isRange(35, 64, false), isTrue);
    expect(buffer.get(80), isTrue);
    expect(() => matrix.get(35, 1), throwsRangeError);
    expect(() => matrix.setRegion(34, 0, 2, 1), throwsArgumentError);
    expect(matrix.get(34, 0), isFalse);
    matrix.flip(34, 2);
    expect(matrix.get(34, 2), isFalse);
    matrix.clear();
    expect(matrix.getRow(1).isRange(0, 35, false), isTrue);
  });
  test('vectors append across byte and capacity boundaries then self-append',
      () {
    final bits = BitVector();
    final expected = StringBuffer();
    for (var i = 0; i < 600; i++) {
      bits.appendBits(i, 11);
      expected.write(i.toRadixString(2).padLeft(11, '0'));
    }
    expect(bits.toString(), expected.toString());
    bits.appendBitVector(bits);
    expect(bits.toString(), '${expected.toString()}${expected.toString()}');
    expect(bits.sizeInBytes(), (bits.size() + 7) ~/ 8);
  });
  test('vector XOR supports partial byte, signed input and aliased operand',
      () {
    final a = BitVector()
      ..appendBits(-1, 32)
      ..appendBits(5, 3);
    final b = BitVector()
      ..appendBits(0, 32)
      ..appendBits(3, 3);
    a.xor(b);
    expect(a.toString(), '${'1' * 32}110');
    a.xor(a);
    expect(a.toString(), '0' * 35);
    expect(() => a.xor(BitVector()), throwsArgumentError);
    expect(() => a.appendBits(0, 33), throwsArgumentError);
  });
}
