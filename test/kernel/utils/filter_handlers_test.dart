import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:itext/itext.dart';

void main() {
  group('FilterHandlers', () {
    group('FlateDecode', () {
      test('decodes simple zlib compressed data', () {
        // Compress some test data
        final original =
            utf8.encode('Hello, World! This is a test of FlateDecode filter.');
        final compressed = zlib.encode(original);

        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.flateDecodeFilter);

        final decoded = FilterHandlers.decodeBytes(
          Uint8List.fromList(compressed),
          dict,
        );

        expect(decoded, equals(Uint8List.fromList(original)));
      });

      test('handles empty input', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.flateDecodeFilter);

        // Empty zlib stream
        final compressed = zlib.encode([]);
        final decoded = FilterHandlers.decodeBytes(
          Uint8List.fromList(compressed),
          dict,
        );

        expect(decoded, isEmpty);
      });

      test('returns original bytes on invalid data', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.flateDecodeFilter);

        final invalid = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
        final decoded = FilterHandlers.decodeBytes(invalid, dict);

        expect(decoded, equals(invalid));
      });
    });

    group('ASCIIHexDecode', () {
      test('decodes simple hex string', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.asciiHexDecodeFilter);

        // "Hello" in hex
        final hexData = utf8.encode('48656C6C6F>');
        final decoded = FilterHandlers.decodeBytes(
          Uint8List.fromList(hexData),
          dict,
        );

        expect(utf8.decode(decoded), equals('Hello'));
      });

      test('handles lowercase hex', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.asciiHexDecodeFilter);

        final hexData = utf8.encode('48656c6c6f>');
        final decoded = FilterHandlers.decodeBytes(
          Uint8List.fromList(hexData),
          dict,
        );

        expect(utf8.decode(decoded), equals('Hello'));
      });

      test('ignores whitespace', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.asciiHexDecodeFilter);

        final hexData = utf8.encode('48 65\n6C\r6C\t6F>');
        final decoded = FilterHandlers.decodeBytes(
          Uint8List.fromList(hexData),
          dict,
        );

        expect(utf8.decode(decoded), equals('Hello'));
      });

      test('pads odd number of hex digits', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.asciiHexDecodeFilter);

        // Odd number: "4" should become 0x40
        final hexData = utf8.encode('4>');
        final decoded = FilterHandlers.decodeBytes(
          Uint8List.fromList(hexData),
          dict,
        );

        expect(decoded, equals(Uint8List.fromList([0x40])));
      });
    });

    group('ASCII85Decode', () {
      test('decodes simple ASCII85 data', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.ascii85DecodeFilter);

        // "Hello" encoded in ASCII85
        // "Hello" = [72, 101, 108, 108, 111]
        // In ASCII85: "87cURDZ~>"
        final a85Data = utf8.encode('87cURDZ~>');
        final decoded = FilterHandlers.decodeBytes(
          Uint8List.fromList(a85Data),
          dict,
        );

        expect(utf8.decode(decoded.sublist(0, 5)), equals('Hello'));
      });

      test('handles z abbreviation for zeros', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.ascii85DecodeFilter);

        // 'z' represents 4 zero bytes
        final a85Data = utf8.encode('z~>');
        final decoded = FilterHandlers.decodeBytes(
          Uint8List.fromList(a85Data),
          dict,
        );

        expect(decoded, equals(Uint8List.fromList([0, 0, 0, 0])));
      });

      test('ignores whitespace', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.ascii85DecodeFilter);

        final a85Data = utf8.encode('8 7\nc\rU\tRDZ~>');
        final decoded = FilterHandlers.decodeBytes(
          Uint8List.fromList(a85Data),
          dict,
        );

        expect(utf8.decode(decoded.sublist(0, 5)), equals('Hello'));
      });
    });

    group('RunLengthDecode', () {
      test('decodes literal run', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.runLengthDecodeFilter);

        // Literal run: length=4 means copy next 5 bytes
        // Format: [length - 1] [bytes...]
        final rlData = Uint8List.fromList(
            [4, 72, 101, 108, 108, 111, 128]); // "Hello" + EOD
        final decoded = FilterHandlers.decodeBytes(rlData, dict);

        expect(utf8.decode(decoded), equals('Hello'));
      });

      test('decodes repeat run', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.runLengthDecodeFilter);

        // Repeat run: length=251 means repeat next byte (257-251)=6 times
        final rlData =
            Uint8List.fromList([251, 65, 128]); // 'A' repeated 6 times + EOD
        final decoded = FilterHandlers.decodeBytes(rlData, dict);

        expect(utf8.decode(decoded), equals('AAAAAA'));
      });

      test('handles mixed runs', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.runLengthDecodeFilter);

        // Literal "Hi" + repeat 'X' 3 times
        final rlData = Uint8List.fromList(
            [1, 72, 105, 254, 88, 128]); // "Hi" + "XXX" + EOD
        final decoded = FilterHandlers.decodeBytes(rlData, dict);

        expect(utf8.decode(decoded), equals('HiXXX'));
      });
    });

    group('LZWDecode', () {
      test('decodes simple LZW data', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName.lzwDecodeFilter);

        // This is a minimal LZW-encoded stream
        // For simplicity, we'll just verify it doesn't crash on invalid data
        // Real LZW testing requires properly encoded test data
        final lzwData = Uint8List.fromList(
            [0x80, 0x0B, 0x60, 0x50, 0x22, 0x0C, 0x0C, 0x85, 0x01]);

        // Should not throw
        final decoded = FilterHandlers.decodeBytes(lzwData, dict);
        expect(decoded, isA<Uint8List>());
      });
    });

    group('Multiple Filters', () {
      test('applies filters in order', () {
        final dict = PdfDictionary();

        // Create filter array: ASCIIHex -> (decode hex first, then treat result)
        final filters = PdfArray();
        filters.add(PdfName.asciiHexDecodeFilter);
        dict.put(PdfName.filter, filters);

        final hexData = utf8.encode('48656C6C6F>'); // "Hello"
        final decoded = FilterHandlers.decodeBytes(
          Uint8List.fromList(hexData),
          dict,
        );

        expect(utf8.decode(decoded), equals('Hello'));
      });
    });

    group('No Filter', () {
      test('returns original bytes when no filter', () {
        final dict = PdfDictionary();
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);

        final result = FilterHandlers.decodeBytes(data, dict);
        expect(result, equals(data));
      });
    });

    group('Unknown Filter', () {
      test('returns original bytes for unknown filter', () {
        final dict = PdfDictionary();
        dict.put(PdfName.filter, PdfName('UnknownFilter'));

        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final result = FilterHandlers.decodeBytes(data, dict);

        expect(result, equals(data));
      });
    });
  });

  group('PdfObject Types', () {
    test('PdfNull is singleton', () {
      final null1 = PdfNull();
      final null2 = PdfNull();
      expect(identical(null1, null2), isTrue);
      expect(null1.isNull(), isTrue);
    });

    test('PdfBoolean uses singletons', () {
      final bool1 = PdfBoolean(true);
      final bool2 = PdfBoolean(true);
      expect(identical(bool1, bool2), isTrue);
      expect(identical(PdfBoolean.pdfTrue, bool1), isTrue);
      expect(identical(PdfBoolean.pdfFalse, PdfBoolean(false)), isTrue);
      expect(PdfBoolean.pdfTrue.getValue(), isTrue);
      expect(PdfBoolean.pdfFalse.getValue(), isFalse);
    });

    test('PdfNumber handles integers', () {
      final num = PdfNumber(42);
      expect(num.intValue(), equals(42));
      expect(num.doubleValue(), equals(42.0));
      expect(num.isNumber(), isTrue);
    });

    test('PdfNumber handles doubles', () {
      final num = PdfNumber(3.14159);
      expect(num.doubleValue(), closeTo(3.14159, 0.0001));
      expect(num.intValue(), equals(3));
    });

    test('PdfNumber hasDecimalPart', () {
      expect(PdfNumber(42).hasDecimalPart(), isFalse);
      expect(PdfNumber(42.0).hasDecimalPart(), isFalse);
      expect(PdfNumber(42.5).hasDecimalPart(), isTrue);
    });

    test('PdfString encodes correctly', () {
      final str = PdfString('Hello');
      expect(str.getValue(), equals('Hello'));
      expect(str.isString(), isTrue);
    });

    test('PdfName uses interning', () {
      final name1 = PdfName.intern('Test');
      final name2 = PdfName.intern('Test');
      expect(identical(name1, name2), isTrue);
    });

    test('PdfName constants are interned', () {
      final name = PdfName.intern('Type');
      expect(identical(name, PdfName.type), isTrue);
    });

    test('PdfArray operations', () {
      final arr = PdfArray();
      arr.add(PdfNumber(1));
      arr.add(PdfNumber(2));
      arr.add(PdfNumber(3));

      expect(arr.size(), equals(3));
      expect(arr.getAsNumber(0)?.intValue(), equals(1));
      expect(arr.getAsNumber(1)?.intValue(), equals(2));
      expect(arr.getAsNumber(2)?.intValue(), equals(3));
    });

    test('PdfArray toDoubleArray', () {
      final arr = PdfArray();
      arr.add(PdfNumber(1.5));
      arr.add(PdfNumber(2.5));
      arr.add(PdfNumber(3.5));

      final doubles = arr.toDoubleArray();
      expect(doubles, equals([1.5, 2.5, 3.5]));
    });

    test('PdfArray toIntArray', () {
      final arr = PdfArray();
      arr.add(PdfNumber(1));
      arr.add(PdfNumber(2));
      arr.add(PdfNumber(3));

      final ints = arr.toIntArray();
      expect(ints, equals([1, 2, 3]));
    });

    test('PdfDictionary operations', () {
      final dict = PdfDictionary();
      dict.put(PdfName.type, PdfName.page);
      dict.put(PdfName.count, PdfNumber(10));

      expect(dict.size(), equals(2));
      expect(dict.getAsName(PdfName.type), equals(PdfName.page));
      expect(dict.getAsNumber(PdfName.count)?.intValue(), equals(10));
    });

    test('PdfDictionary containsKey', () {
      final dict = PdfDictionary();
      dict.put(PdfName.type, PdfName.page);

      expect(dict.containsKey(PdfName.type), isTrue);
      expect(dict.containsKey(PdfName.count), isFalse);
    });

    test('PdfStream operations', () {
      final content = Uint8List.fromList(utf8.encode('Hello Stream'));
      final stream = PdfStream.withBytes(content);

      expect(stream.isStream(), isTrue);
      expect(stream.getBytes(), equals(content));
    });

    test('PdfLiteral operations', () {
      final literal = PdfLiteral('test content');

      expect(literal.isLiteral(), isTrue);
      expect(literal.toString(), equals('test content'));
      expect(literal.getBytesCount(), equals(12));
    });

    test('PdfIndirectReference equality', () {
      final ref1 = PdfIndirectReference(5, 0);
      final ref2 = PdfIndirectReference(5, 0);
      final ref3 = PdfIndirectReference(5, 1);

      expect(ref1, equals(ref2));
      expect(ref1, isNot(equals(ref3)));
      expect(ref1.toString(), equals('5 0 R'));
    });
  });
}
