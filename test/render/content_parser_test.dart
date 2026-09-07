import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_null.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/render/content_parser.dart';
import 'package:test/test.dart';

List<PdfContentOperation> _parse(String content) =>
    PdfContentParser.parse(Uint8List.fromList(latin1.encode(content))).toList();

void main() {
  group('PdfContentParser', () {
    test('splits operands from the operator that follows them', () {
      final ops = _parse('1 0 0 1 72 720 cm');

      expect(ops, hasLength(1));
      expect(ops.single.operator, equals('cm'));
      expect(ops.single.numbers(6), equals([1, 0, 0, 1, 72, 720]));
    });

    test('reads a whole path-painting sequence in order', () {
      final ops = _parse('q 0.5 g 10 20 m 30 40 l h f Q');

      expect(ops.map((o) => o.operator),
          equals(['q', 'g', 'm', 'l', 'h', 'f', 'Q']));
      expect(ops[1].number(0), equals(0.5));
      expect(ops[2].numbers(2), equals([10, 20]));
    });

    test('reads names, including hex escapes', () {
      final ops = _parse('/DeviceRGB cs /A#20B Do');

      expect(ops[0].name(0), equals('DeviceRGB'));
      expect(ops[1].name(0), equals('A B'));
    });

    test('reads literal strings with escapes and nesting', () {
      final ops = _parse(r'(plain) (a\(b\)c) (line\nbreak) (\101\102) Tj');

      final strings =
          ops.single.operands.cast<PdfString>().map((s) => s.getValue());
      expect(strings, equals(['plain', 'a(b)c', 'line\nbreak', 'AB']));
    });

    test('reads hex strings, padding an odd trailing digit', () {
      final ops = _parse('<48656C6C6F> <41 42> <4> Tj');

      final bytes = ops.single.operands
          .cast<PdfString>()
          .map((s) => s.getValueBytes()!.toList())
          .toList();
      expect(bytes.first, equals('Hello'.codeUnits));
      expect(bytes[1], equals([0x41, 0x42]));
      expect(bytes[2], equals([0x40]));
    });

    test('reads arrays, including the mixed kind TJ uses', () {
      final ops = _parse('[(A) -250 (B) 120 (C)] TJ');

      expect(ops.single.operator, equals('TJ'));
      final array = ops.single.operands.single as PdfArray;
      expect(array.size(), equals(5));
    });

    test('reads inline dictionaries', () {
      final ops = _parse('/P0 <</Type /Foo /N 3>> BDC');

      expect(ops.single.operator, equals('BDC'));
      expect(ops.single.operands, hasLength(2));
      expect(ops.single.operands[1], isA<Object>());
    });

    test('reads booleans and null as objects, not operators', () {
      final ops = _parse('true false null Tf');

      expect(ops.single.operands[0], isA<PdfBoolean>());
      expect(ops.single.operands[1], isA<PdfBoolean>());
      expect(ops.single.operands[2], isA<PdfNull>());
    });

    test('skips comments', () {
      final ops = _parse('% a leading comment\n1 2 m % trailing\n3 4 l');

      expect(ops.map((o) => o.operator), equals(['m', 'l']));
      expect(ops.first.numbers(2), equals([1, 2]));
    });

    test('reads negative and fractional numbers', () {
      final ops = _parse('-1.5 +2 .25 -.5 c');

      expect(ops.single.numbers(4), equals([-1.5, 2, 0.25, -0.5]));
    });

    test('reads an inline image, dictionary and samples', () {
      // Four bytes of samples between ID and EI.
      final ops = _parse(
          'q /Fm0 Do BI /W 2 /H 2 /BPC 8 /CS /G ID \x01\x02\x03\x04 EI Q');

      expect(ops.map((o) => o.operator), equals(['q', 'Do', 'BI', 'Q']));
      final image = ops[2];
      expect(image.inlineImage, isNotNull);
      expect(image.inlineImage!.getNumberSync(PdfName('W'))?.intValue(),
          equals(2));
      expect(image.inlineImageData, equals([1, 2, 3, 4]));
    });

    test('does not mistake EI inside a word for the end of an image', () {
      final ops = _parse('BI /W 1 /H 1 ID \x41BEIX\x42 EI Q');

      // "BEIX" contains EI but not at a token boundary.
      expect(ops.first.inlineImageData,
          equals([0x41, 0x42, 0x45, 0x49, 0x58, 0x42]));
      expect(ops.map((o) => o.operator), equals(['BI', 'Q']));
    });

    test('reports where a string is left unterminated', () {
      expect(
        () => _parse('(never closed'),
        throwsA(isA<PdfContentException>()),
      );
    });

    test('reports an unterminated array and dictionary', () {
      expect(() => _parse('[1 2 3'), throwsA(isA<PdfContentException>()));
      expect(() => _parse('<</A 1'), throwsA(isA<PdfContentException>()));
    });

    test('refuses to accumulate operands forever on binary junk', () {
      final junk = List<int>.filled(4000, 0x31); // '1' repeated
      final content = Uint8List.fromList([
        ...latin1.encode('q '),
        ...junk.expand((c) => [c, 0x20])
      ]);

      expect(() => PdfContentParser.parse(content).toList(),
          throwsA(isA<PdfContentException>()));
    });

    test('numbers() rejects a mixed operand list', () {
      final ops = _parse('1 /Name 3 op');

      expect(ops.single.numbers(), isNull);
      expect(ops.single.numbers(3), isNull);
      expect(ops.single.number(0), equals(1));
      expect(ops.single.name(1), equals('Name'));
    });

    test('an operator with no operands still appears', () {
      final ops = _parse('q Q n W* f*');

      expect(ops.map((o) => o.operator), equals(['q', 'Q', 'n', 'W*', 'f*']));
      expect(ops.every((o) => o.operands.isEmpty), isTrue);
    });

    test('parses an empty stream to nothing', () {
      expect(_parse(''), isEmpty);
      expect(_parse('   \n\r\t  '), isEmpty);
    });
  });
}
