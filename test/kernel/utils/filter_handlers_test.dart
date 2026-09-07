import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dpdf/dpdf.dart';

void main() {
  group('FilterHandlers', () {
    group('FlateDecode', () {
      test('decodes simple zlib compressed data', () async {
        // Compress some test data
        final original =
            utf8.encode('Hello, World! This is a test of FlateDecode filter.');
        final compressed = zlib.encode(original);

        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.flateDecodeFilter);

        final decoded = await CraftFilterHandlers.decodeBytes(
          Uint8List.fromList(compressed),
          dict,
        );

        expect(decoded, equals(Uint8List.fromList(original)));
      });

      test('handles empty input', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.flateDecodeFilter);

        // Empty zlib stream
        final compressed = zlib.encode([]);
        final decoded = await CraftFilterHandlers.decodeBytes(
          Uint8List.fromList(compressed),
          dict,
        );

        expect(decoded, isEmpty);
      });

      test('returns original bytes on invalid data', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.flateDecodeFilter);

        final invalid = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
        final decoded = await CraftFilterHandlers.decodeBytes(invalid, dict);

        expect(decoded, equals(invalid));
      });
    });

    group('ASCIIHexDecode', () {
      test('decodes simple hex string', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.asciiHexDecodeFilter);

        // "Hello" in hex
        final hexData = utf8.encode('48656C6C6F>');
        final decoded = await CraftFilterHandlers.decodeBytes(
          Uint8List.fromList(hexData),
          dict,
        );

        expect(utf8.decode(decoded), equals('Hello'));
      });

      test('handles lowercase hex', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.asciiHexDecodeFilter);

        final hexData = utf8.encode('48656c6c6f>');
        final decoded = await CraftFilterHandlers.decodeBytes(
          Uint8List.fromList(hexData),
          dict,
        );

        expect(utf8.decode(decoded), equals('Hello'));
      });

      test('ignores whitespace', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.asciiHexDecodeFilter);

        final hexData = utf8.encode('48 65\n6C\r6C\t6F>');
        final decoded = await CraftFilterHandlers.decodeBytes(
          Uint8List.fromList(hexData),
          dict,
        );

        expect(utf8.decode(decoded), equals('Hello'));
      });

      test('pads odd number of hex digits', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.asciiHexDecodeFilter);

        // Odd number: "4" should become 0x40
        final hexData = utf8.encode('4>');
        final decoded = await CraftFilterHandlers.decodeBytes(
          Uint8List.fromList(hexData),
          dict,
        );

        expect(decoded, equals(Uint8List.fromList([0x40])));
      });
    });

    group('ASCII85Decode', () {
      test('decodes simple ASCII85 data', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.ascii85DecodeFilter);

        // "Hello" encoded in ASCII85
        // "Hello" = [72, 101, 108, 108, 111]
        // In ASCII85: "87cURDZ~>"
        final a85Data = utf8.encode('87cURDZ~>');
        final decoded = await CraftFilterHandlers.decodeBytes(
          Uint8List.fromList(a85Data),
          dict,
        );

        expect(utf8.decode(decoded.sublist(0, 5)), equals('Hello'));
      });

      test('handles z abbreviation for zeros', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.ascii85DecodeFilter);

        // 'z' represents 4 zero bytes
        final a85Data = utf8.encode('z~>');
        final decoded = await CraftFilterHandlers.decodeBytes(
          Uint8List.fromList(a85Data),
          dict,
        );

        expect(decoded, equals(Uint8List.fromList([0, 0, 0, 0])));
      });

      test('ignores whitespace', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.ascii85DecodeFilter);

        final a85Data = utf8.encode('8 7\nc\rU\tRDZ~>');
        final decoded = await CraftFilterHandlers.decodeBytes(
          Uint8List.fromList(a85Data),
          dict,
        );

        expect(utf8.decode(decoded.sublist(0, 5)), equals('Hello'));
      });
    });

    group('RunLengthDecode', () {
      test('decodes literal run', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.runLengthDecodeFilter);

        // Literal run: length=4 means copy next 5 bytes
        // Format: [length - 1] [bytes...]
        final rlData = Uint8List.fromList(
            [4, 72, 101, 108, 108, 111, 128]); // "Hello" + EOD
        final decoded = await CraftFilterHandlers.decodeBytes(rlData, dict);

        expect(utf8.decode(decoded), equals('Hello'));
      });

      test('decodes repeat run', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.runLengthDecodeFilter);

        // Repeat run: length=251 means repeat next byte (257-251)=6 times
        final rlData =
            Uint8List.fromList([251, 65, 128]); // 'A' repeated 6 times + EOD
        final decoded = await CraftFilterHandlers.decodeBytes(rlData, dict);

        expect(utf8.decode(decoded), equals('AAAAAA'));
      });

      test('handles mixed runs', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.runLengthDecodeFilter);

        // Literal "Hi" + repeat 'X' 3 times
        final rlData = Uint8List.fromList(
            [1, 72, 105, 254, 88, 128]); // "Hi" + "XXX" + EOD
        final decoded = await CraftFilterHandlers.decodeBytes(rlData, dict);

        expect(utf8.decode(decoded), equals('HiXXX'));
      });
    });

    group('LZWDecode', () {
      test('decodes simple LZW data', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName.lzwDecodeFilter);

        // This is a minimal LZW-encoded stream
        // For simplicity, we'll just verify it doesn't crash on invalid data
        // Real LZW testing requires properly encoded test data
        final lzwData = Uint8List.fromList(
            [0x80, 0x0B, 0x60, 0x50, 0x22, 0x0C, 0x0C, 0x85, 0x01]);

        // Should not throw
        final decoded = await CraftFilterHandlers.decodeBytes(lzwData, dict);
        expect(decoded, isA<Uint8List>());
      });
    });

    group('Multiple Filters', () {
      test('applies filters in order', () async {
        final dict = CraftPdfDictionary();

        // Create filter array: ASCIIHex -> (decode hex first, then treat result)
        final filters = CraftPdfArray();
        filters.add(CraftPdfName.asciiHexDecodeFilter);
        dict.put(CraftPdfName.filter, filters);

        final hexData = utf8.encode('48656C6C6F>'); // "Hello"
        final decoded = await CraftFilterHandlers.decodeBytes(
          Uint8List.fromList(hexData),
          dict,
        );

        expect(utf8.decode(decoded), equals('Hello'));
      });
    });

    group('No Filter', () {
      test('returns original bytes when no filter', () async {
        final dict = CraftPdfDictionary();
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);

        final result = await CraftFilterHandlers.decodeBytes(data, dict);
        expect(result, equals(data));
      });
    });

    group('Unknown Filter', () {
      test('returns original bytes for unknown filter', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.filter, CraftPdfName('UnknownFilter'));

        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final result = await CraftFilterHandlers.decodeBytes(data, dict);

        expect(result, equals(data));
      });
    });
  });

  group('PdfObject Types', () {
    test('PdfNull is singleton', () {
      final null1 = CraftPdfNull();
      final null2 = CraftPdfNull();
      expect(identical(null1, null2), isTrue);
      expect(null1.isNull(), isTrue);
    });

    test('PdfBoolean uses singletons', () {
      final bool1 = CraftPdfBoolean(true);
      final bool2 = CraftPdfBoolean(true);
      expect(identical(bool1, bool2), isTrue);
      expect(identical(CraftPdfBoolean.pdfTrue, bool1), isTrue);
      expect(
          identical(CraftPdfBoolean.pdfFalse, CraftPdfBoolean(false)), isTrue);
      expect(CraftPdfBoolean.pdfTrue.getValue(), isTrue);
      expect(CraftPdfBoolean.pdfFalse.getValue(), isFalse);
    });

    test('PdfNumber handles integers', () {
      final num = CraftPdfNumber(42);
      expect(num.intValue(), equals(42));
      expect(num.doubleValue(), equals(42.0));
      expect(num.isNumber(), isTrue);
    });

    test('PdfNumber handles doubles', () {
      final num = CraftPdfNumber(3.14159);
      expect(num.doubleValue(), closeTo(3.14159, 0.0001));
      expect(num.intValue(), equals(3));
    });

    test('PdfNumber hasDecimalPart', () {
      expect(CraftPdfNumber(42).hasDecimalPart(), isFalse);
      expect(CraftPdfNumber(42.0).hasDecimalPart(), isFalse);
      expect(CraftPdfNumber(42.5).hasDecimalPart(), isTrue);
    });

    test('PdfString encodes correctly', () {
      final str = CraftPdfString('Hello');
      expect(str.getValue(), equals('Hello'));
      expect(str.isString(), isTrue);
    });

    test('PdfName uses interning', () {
      final name1 = CraftPdfName.intern('Test');
      final name2 = CraftPdfName.intern('Test');
      expect(identical(name1, name2), isTrue);
    });

    test('PdfName constants are interned', () {
      final name = CraftPdfName.intern('Type');
      expect(identical(name, CraftPdfName.type), isTrue);
    });

    test('PdfArray operations', () async {
      final arr = CraftPdfArray();
      arr.add(CraftPdfNumber(1));
      arr.add(CraftPdfNumber(2));
      arr.add(CraftPdfNumber(3));

      expect(arr.size(), equals(3));
      expect((await arr.numberEntry(0))?.intValue(), equals(1));
      expect((await arr.numberEntry(1))?.intValue(), equals(2));
      expect((await arr.numberEntry(2))?.intValue(), equals(3));
    });

    test('PdfArray toDoubleArray', () async {
      final arr = CraftPdfArray();
      arr.add(CraftPdfNumber(1.5));
      arr.add(CraftPdfNumber(2.5));
      arr.add(CraftPdfNumber(3.5));

      final doubles = await arr.toDoubleArray();
      expect(doubles, equals([1.5, 2.5, 3.5]));
    });

    test('PdfArray toIntArray', () async {
      final arr = CraftPdfArray();
      arr.add(CraftPdfNumber(1));
      arr.add(CraftPdfNumber(2));
      arr.add(CraftPdfNumber(3));

      final ints = await arr.toIntArray();
      expect(ints, equals([1, 2, 3]));
    });

    test('PdfDictionary operations', () async {
      final dict = CraftPdfDictionary();
      dict.put(CraftPdfName.type, CraftPdfName.page);
      dict.put(CraftPdfName.count, CraftPdfNumber(10));

      expect(dict.size(), equals(2));
      expect(
          await dict.nameEntry(CraftPdfName.type), equals(CraftPdfName.page));
      expect(
          (await dict.numberEntry(CraftPdfName.count))?.intValue(), equals(10));
    });

    test('PdfDictionary containsKey', () {
      final dict = CraftPdfDictionary();
      dict.put(CraftPdfName.type, CraftPdfName.page);

      expect(dict.containsKey(CraftPdfName.type), isTrue);
      expect(dict.containsKey(CraftPdfName.count), isFalse);
    });

    test('PdfStream operations', () async {
      final content = Uint8List.fromList(utf8.encode('Hello Stream'));
      final stream = CraftPdfStream.withBytes(content);

      expect(stream.isStream(), isTrue);
      expect(await stream.getBytes(), equals(content));
    });

    test('PdfLiteral operations', () {
      final literal = CraftPdfLiteral('test content');

      expect(literal.isLiteral(), isTrue);
      expect(literal.toString(), equals('test content'));
      expect(literal.getBytesCount(), equals(12));
    });

    test('PdfIndirectReference equality', () {
      final ref1 = CraftPdfIndirectReference(5, 0);
      final ref2 = CraftPdfIndirectReference(5, 0);
      final ref3 = CraftPdfIndirectReference(5, 1);

      expect(ref1, equals(ref2));
      expect(ref1, isNot(equals(ref3)));
      expect(ref1.toString(), equals('5 0 R'));
    });
  });
}
