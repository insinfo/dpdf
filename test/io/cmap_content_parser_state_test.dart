import 'dart:convert';
import 'dart:typed_data';
import 'package:pdfcraft/pdfcraft.dart';
import 'package:pdfcraft/src/io/font/cmap/cmap_content_parser.dart';
import 'package:pdfcraft/src/io/font/cmap/cmap_object.dart';
import 'package:test/test.dart';

CraftCMapContentParser parser(String text) =>
    CraftCMapContentParser(CraftPdfTokenizer(
        CraftRandomAccessFileOrArray(Uint8List.fromList(ascii.encode(text)))));

void main() {
  for (final asynchronous in [false, true]) {
    final mode = asynchronous ? 'async' : 'sync';
    Future<CraftCMapObject?> read(String text) async {
      final input = parser(text);
      return asynchronous ? await input.readObject() : input.readObjectSync();
    }

    test('$mode nested CMap objects preserve decimals and decoded keys',
        () async {
      final result = await read(
          '<< /A#20B [0.125 << /Text (a\\n\\050b\\051) >> <4142>] >>');
      final dictionary = result!.getValue() as Map<String, CraftCMapObject>;
      final values = dictionary['A B']!.getValue() as List<CraftCMapObject>;
      expect(values[0].getValue(), 0.125);
      final nested = values[1].getValue() as Map<String, CraftCMapObject>;
      expect(nested['Text']!.getValue(), [97, 10, 40, 98, 41]);
      expect(values[2].getValue(), [65, 66]);
    });
    test('$mode malformed containers reject incomplete or mismatched syntax',
        () async {
      for (final text in [
        '[',
        '<<',
        '[ >>',
        '<< ]',
        '<< /A >>',
        '<< /A ]',
        '<< 1 2 >>',
        '<< [] 2 >>'
      ]) {
        await expectLater(read(text), throwsFormatException, reason: text);
      }
    });
    test('$mode parser returns successive commands and skips comments',
        () async {
      final input = parser('% ignored\n /A 3 def [1 2] use');
      final operands = <CraftCMapObject>[];
      if (asynchronous) {
        await input.parse(operands);
      } else {
        input.parseSync(operands);
      }
      expect(operands.map((v) => v.toString()), ['A', '3', 'def']);
      if (asynchronous) {
        await input.parse(operands);
      } else {
        input.parseSync(operands);
      }
      expect(operands.length, 2);
      expect(operands.last.getValue(), 'use');
    });
    test('$mode rejects standalone closers and excessive depth', () async {
      final input = parser(']');
      if (asynchronous) {
        await expectLater(input.parse([]), throwsFormatException);
      } else {
        expect(() => input.parseSync([]), throwsFormatException);
      }
      await expectLater(
          read(
              '${List.filled(257, '[').join()}${List.filled(257, ']').join()}'),
          throwsFormatException);
    });
  }
}
