/// PDF primitives unit tests ported from iText .NET
/// See: itext.tests/itext.kernel.tests/itext/kernel/pdf/PdfPrimitivesTest.cs
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dpdf/dpdf.dart';

void main() {
  group('PdfPrimitives', () {
    group('PdfNumber', () {
      test('creates integer number', () {
        final num = PdfNumber.fromInt(42);
        expect(num.intValue(), equals(42));
        expect(num.doubleValue(), equals(42.0));
      });

      test('creates float number', () {
        final num = PdfNumber(3.14159);
        expect(num.doubleValue(), closeTo(3.14159, 0.00001));
      });

      test('increment modifies value', () {
        final num = PdfNumber(1.0);
        num.increment();
        expect(num.intValue(), equals(2));
      });

      test('equal numbers are equal', () {
        final a = PdfNumber(42.0);
        final b = PdfNumber(42.0);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different numbers are not equal', () {
        final a = PdfNumber(42.0);
        final b = PdfNumber(43.0);
        expect(a, isNot(equals(b)));
      });

      test('negative numbers are handled', () {
        final num = PdfNumber(-123.0);
        expect(num.intValue(), equals(-123));
      });

      test('large numbers are handled', () {
        final num = PdfNumber.fromInt(2147483647); // max int32
        expect(num.intValue(), equals(2147483647));
      });

      test('getObjectType returns Number', () {
        final num = PdfNumber(1.0);
        expect(num.getObjectType(), equals(PdfObjectType.number));
      });
    });

    group('PdfString', () {
      test('creates string from value', () {
        final str = PdfString('Hello World');
        expect(str.getValue(), equals('Hello World'));
      });

      test('creates string from bytes', () {
        final bytes = Uint8List.fromList([72, 101, 108, 108, 111]); // "Hello"
        final str = PdfString.fromBytes(bytes);
        expect(str.getValue(), equals('Hello'));
      });

      test('hex strings are identified', () {
        // Create a hex string with setHexWriting
        final str = PdfString('Hello').setHexWriting(true);
        expect(str.isHexWriting(), isTrue);
      });

      test('equal strings are equal', () {
        final a = PdfString('abcd');
        final b = PdfString('abcd');
        expect(a, equals(b));
      });

      test('different strings are not equal', () {
        final a = PdfString('abcd');
        final b = PdfString('efgh');
        expect(a, isNot(equals(b)));
      });

      test('getObjectType returns String', () {
        final str = PdfString('test');
        expect(str.getObjectType(), equals(PdfObjectType.string));
      });

      test('empty string is handled', () {
        final str = PdfString('');
        expect(str.getValue(), equals(''));
      });

      test('string with special characters', () {
        final str = PdfString('Hello (World)');
        expect(str.getValue(), equals('Hello (World)'));
      });
    });

    group('PdfName', () {
      test('creates name', () {
        final name = PdfName('Type');
        expect(name.getValue(), equals('Type'));
      });

      test('equal names are equal', () {
        final a = PdfName('Catalog');
        final b = PdfName('Catalog');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different names are not equal', () {
        final a = PdfName('Type');
        final b = PdfName('Subtype');
        expect(a, isNot(equals(b)));
      });

      test('predefined names are cached', () {
        // Access same constant twice should return same instance
        expect(identical(PdfName.type, PdfName.type), isTrue);
        expect(identical(PdfName.catalog, PdfName.catalog), isTrue);
      });

      test('getObjectType returns Name', () {
        final name = PdfName('Test');
        expect(name.getObjectType(), equals(PdfObjectType.name));
      });

      test('name with numbers', () {
        final name = PdfName('Font1');
        expect(name.getValue(), equals('Font1'));
      });

      test('name with special characters encoded', () {
        // Names can contain hex-encoded characters with #
        final name = PdfName('Name#20With#20Space');
        expect(name.getValue(), isNotNull);
      });
    });

    group('PdfBoolean', () {
      test('creates true', () {
        final t = PdfBoolean(true);
        expect(t.getValue(), isTrue);
      });

      test('creates false', () {
        final f = PdfBoolean(false);
        expect(f.getValue(), isFalse);
      });

      test('singletons exist', () {
        expect(PdfBoolean.pdfTrue.getValue(), isTrue);
        expect(PdfBoolean.pdfFalse.getValue(), isFalse);
      });

      test('factory returns singletons', () {
        expect(identical(PdfBoolean(true), PdfBoolean.pdfTrue), isTrue);
        expect(identical(PdfBoolean(false), PdfBoolean.pdfFalse), isTrue);
      });

      test('equal booleans are equal', () {
        final a = PdfBoolean(true);
        final b = PdfBoolean(true);
        expect(a, equals(b));

        final c = PdfBoolean(false);
        final d = PdfBoolean(false);
        expect(c, equals(d));
      });

      test('different booleans are not equal', () {
        final t = PdfBoolean(true);
        final f = PdfBoolean(false);
        expect(t, isNot(equals(f)));
      });

      test('getObjectType returns Boolean', () {
        expect(PdfBoolean(true).getObjectType(), equals(PdfObjectType.boolean));
      });
    });

    group('PdfNull', () {
      test('singleton exists', () {
        expect(PdfNull.pdfNull, isNotNull);
      });

      test('all nulls are equal', () {
        final a = PdfNull();
        final b = PdfNull();
        expect(a, equals(b));
        expect(a, equals(PdfNull.pdfNull));
      });

      test('getObjectType returns Null', () {
        expect(PdfNull.pdfNull.getObjectType(), equals(PdfObjectType.nullType));
      });
    });

    group('PdfLiteral', () {
      test('creates literal from string', () {
        final lit = PdfLiteral('obj');
        expect(lit.getInternalContent(), isNotNull);
      });

      test('creates literal from bytes', () {
        final bytes = Uint8List.fromList([111, 98, 106]); // "obj"
        final lit = PdfLiteral.fromBytes(bytes);
        expect(lit.getInternalContent(), equals(bytes));
      });

      test('equal literals are equal', () {
        final a = PdfLiteral('stream');
        final b = PdfLiteral('stream');
        expect(a, equals(b));
      });

      test('different literals are not equal', () {
        final a = PdfLiteral('stream');
        final b = PdfLiteral('endstream');
        expect(a, isNot(equals(b)));
      });

      test('getObjectType returns Literal', () {
        expect(
            PdfLiteral('test').getObjectType(), equals(PdfObjectType.literal));
      });
    });

    group('PdfArray', () {
      test('creates empty array', () {
        final arr = PdfArray();
        expect(arr.size(), equals(0));
      });

      test('adds elements', () async {
        final arr = PdfArray();
        arr.add(PdfNumber(1.0));
        arr.add(PdfNumber(2.0));
        arr.add(PdfNumber(3.0));
        expect(arr.size(), equals(3));
      });

      test('gets element by index', () async {
        final arr = PdfArray();
        arr.add(PdfNumber(42.0));
        final elem = await arr.get(0);
        expect(elem, isA<PdfNumber>());
        expect((elem as PdfNumber).intValue(), equals(42));
      });

      test('contains element', () async {
        final arr = PdfArray();
        final num = PdfNumber(42.0);
        arr.add(num);
        expect(await arr.containsObject(num), isTrue);
      });

      test('removes element', () async {
        final arr = PdfArray();
        final num = PdfNumber(42.0);
        arr.add(num);
        await arr.remove(num);
        expect(arr.size(), equals(0));
      });

      test('getAsNumber works', () async {
        final arr = PdfArray();
        arr.add(PdfNumber(123.0));
        final num = await arr.getAsNumber(0);
        expect(num?.intValue(), equals(123));
      });

      test('getAsString works', () async {
        final arr = PdfArray();
        arr.add(PdfString('hello'));
        final str = await arr.getAsString(0);
        expect(str?.getValue(), equals('hello'));
      });

      test('getAsDictionary works', () async {
        final arr = PdfArray();
        final dict = PdfDictionary();
        dict.put(PdfName.type, PdfName.page);
        arr.add(dict);
        final d = await arr.getAsDictionary(0);
        expect(d, isNotNull);
      });

      test('getObjectType returns Array', () {
        final arr = PdfArray();
        expect(arr.getObjectType(), equals(PdfObjectType.array));
      });
    });

    group('PdfDictionary', () {
      test('creates empty dictionary', () {
        final dict = PdfDictionary();
        expect(dict.size(), equals(0));
      });

      test('puts and gets values', () async {
        final dict = PdfDictionary();
        dict.put(PdfName('Key'), PdfNumber(42.0));
        final value = await dict.get(PdfName('Key'));
        expect(value, isA<PdfNumber>());
        expect((value as PdfNumber).intValue(), equals(42));
      });

      test('contains key', () {
        final dict = PdfDictionary();
        dict.put(PdfName('Key'), PdfNumber(42.0));
        expect(dict.containsKey(PdfName('Key')), isTrue);
        expect(dict.containsKey(PdfName('Other')), isFalse);
      });

      test('removes key', () {
        final dict = PdfDictionary();
        dict.put(PdfName('Key'), PdfNumber(42.0));
        dict.remove(PdfName('Key'));
        expect(dict.containsKey(PdfName('Key')), isFalse);
      });

      test('getAsNumber works', () async {
        final dict = PdfDictionary();
        dict.put(PdfName('Count'), PdfNumber(5.0));
        final num = await dict.getAsNumber(PdfName('Count'));
        expect(num?.intValue(), equals(5));
      });

      test('getAsString works', () async {
        final dict = PdfDictionary();
        dict.put(PdfName('Title'), PdfString('Test Document'));
        final str = await dict.getAsString(PdfName('Title'));
        expect(str?.getValue(), equals('Test Document'));
      });

      test('getAsName works', () async {
        final dict = PdfDictionary();
        dict.put(PdfName.type, PdfName.catalog);
        final name = await dict.getAsName(PdfName.type);
        expect(name, equals(PdfName.catalog));
      });

      test('getAsDictionary works', () async {
        final dict = PdfDictionary();
        final nested = PdfDictionary();
        nested.put(PdfName('Inner'), PdfNumber(1.0));
        dict.put(PdfName('Nested'), nested);
        final d = await dict.getAsDictionary(PdfName('Nested'));
        expect(d, isNotNull);
      });

      test('getAsArray works', () async {
        final dict = PdfDictionary();
        final arr = PdfArray()..add(PdfNumber(1.0));
        dict.put(PdfName('Kids'), arr);
        final a = await dict.getAsArray(PdfName('Kids'));
        expect(a, isNotNull);
        expect(a?.size(), equals(1));
      });

      test('keySet returns all keys', () {
        final dict = PdfDictionary();
        dict.put(PdfName('A'), PdfNumber(1.0));
        dict.put(PdfName('B'), PdfNumber(2.0));
        final keys = dict.keySet();
        expect(keys.length, equals(2));
      });

      test('getObjectType returns Dictionary', () {
        final dict = PdfDictionary();
        expect(dict.getObjectType(), equals(PdfObjectType.dictionary));
      });
    });
  });
}
