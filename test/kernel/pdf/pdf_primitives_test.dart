/// Serialization and value semantics for PDF primitives.
/// See: dpdf.tests/dpdf.kernel.tests/dpdf/kernel/pdf/PdfPrimitivesTest.cs
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dpdf/dpdf.dart';

void main() {
  group('PdfPrimitives', () {
    group('PdfNumber', () {
      test('creates integer number', () {
        final num = CraftPdfNumber.fromInt(42);
        expect(num.intValue(), equals(42));
        expect(num.doubleValue(), equals(42.0));
      });

      test('creates float number', () {
        final num = CraftPdfNumber(3.14159);
        expect(num.doubleValue(), closeTo(3.14159, 0.00001));
      });

      test('increment modifies value', () {
        final num = CraftPdfNumber(1.0);
        num.increment();
        expect(num.intValue(), equals(2));
      });

      test('equal numbers are equal', () {
        final a = CraftPdfNumber(42.0);
        final b = CraftPdfNumber(42.0);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different numbers are not equal', () {
        final a = CraftPdfNumber(42.0);
        final b = CraftPdfNumber(43.0);
        expect(a, isNot(equals(b)));
      });

      test('negative numbers are handled', () {
        final num = CraftPdfNumber(-123.0);
        expect(num.intValue(), equals(-123));
      });

      test('large numbers are handled', () {
        final num = CraftPdfNumber.fromInt(2147483647); // max int32
        expect(num.intValue(), equals(2147483647));
      });

      test('getObjectType returns Number', () {
        final num = CraftPdfNumber(1.0);
        expect(num.objectKind(), equals(PdfObjectType.number));
      });
    });

    group('PdfString', () {
      test('creates string from value', () {
        final str = CraftPdfString('Hello World');
        expect(str.getValue(), equals('Hello World'));
      });

      test('creates string from bytes', () {
        final bytes = Uint8List.fromList([72, 101, 108, 108, 111]); // "Hello"
        final str = CraftPdfString.fromBytes(bytes);
        expect(str.getValue(), equals('Hello'));
      });

      test('hex strings are identified', () {
        // Create a hex string with setHexWriting
        final str = CraftPdfString('Hello').setHexWriting(true);
        expect(str.isHexWriting(), isTrue);
      });

      test('equal strings are equal', () {
        final a = CraftPdfString('abcd');
        final b = CraftPdfString('abcd');
        expect(a, equals(b));
      });

      test('different strings are not equal', () {
        final a = CraftPdfString('abcd');
        final b = CraftPdfString('efgh');
        expect(a, isNot(equals(b)));
      });

      test('getObjectType returns String', () {
        final str = CraftPdfString('test');
        expect(str.objectKind(), equals(PdfObjectType.string));
      });

      test('empty string is handled', () {
        final str = CraftPdfString('');
        expect(str.getValue(), equals(''));
      });

      test('string with special characters', () {
        final str = CraftPdfString('Hello (World)');
        expect(str.getValue(), equals('Hello (World)'));
      });
    });

    group('PdfName', () {
      test('creates name', () {
        final name = CraftPdfName('Type');
        expect(name.getValue(), equals('Type'));
      });

      test('equal names are equal', () {
        final a = CraftPdfName('Catalog');
        final b = CraftPdfName('Catalog');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different names are not equal', () {
        final a = CraftPdfName('Type');
        final b = CraftPdfName('Subtype');
        expect(a, isNot(equals(b)));
      });

      test('predefined names are cached', () {
        // Access same constant twice should return same instance
        expect(identical(CraftPdfName.type, CraftPdfName.type), isTrue);
        expect(identical(CraftPdfName.catalog, CraftPdfName.catalog), isTrue);
      });

      test('getObjectType returns Name', () {
        final name = CraftPdfName('Test');
        expect(name.objectKind(), equals(PdfObjectType.name));
      });

      test('name with numbers', () {
        final name = CraftPdfName('Font1');
        expect(name.getValue(), equals('Font1'));
      });

      test('name with special characters encoded', () {
        // Names can contain hex-encoded characters with #
        final name = CraftPdfName('Name#20With#20Space');
        expect(name.getValue(), isNotNull);
      });
    });

    group('PdfBoolean', () {
      test('creates true', () {
        final t = CraftPdfBoolean(true);
        expect(t.getValue(), isTrue);
      });

      test('creates false', () {
        final f = CraftPdfBoolean(false);
        expect(f.getValue(), isFalse);
      });

      test('singletons exist', () {
        expect(CraftPdfBoolean.pdfTrue.getValue(), isTrue);
        expect(CraftPdfBoolean.pdfFalse.getValue(), isFalse);
      });

      test('factory returns singletons', () {
        expect(
            identical(CraftPdfBoolean(true), CraftPdfBoolean.pdfTrue), isTrue);
        expect(identical(CraftPdfBoolean(false), CraftPdfBoolean.pdfFalse),
            isTrue);
      });

      test('equal booleans are equal', () {
        final a = CraftPdfBoolean(true);
        final b = CraftPdfBoolean(true);
        expect(a, equals(b));

        final c = CraftPdfBoolean(false);
        final d = CraftPdfBoolean(false);
        expect(c, equals(d));
      });

      test('different booleans are not equal', () {
        final t = CraftPdfBoolean(true);
        final f = CraftPdfBoolean(false);
        expect(t, isNot(equals(f)));
      });

      test('getObjectType returns Boolean', () {
        expect(
            CraftPdfBoolean(true).objectKind(), equals(PdfObjectType.boolean));
      });
    });

    group('PdfNull', () {
      test('singleton exists', () {
        expect(CraftPdfNull.pdfNull, isNotNull);
      });

      test('all nulls are equal', () {
        final a = CraftPdfNull();
        final b = CraftPdfNull();
        expect(a, equals(b));
        expect(a, equals(CraftPdfNull.pdfNull));
      });

      test('getObjectType returns Null', () {
        expect(
            CraftPdfNull.pdfNull.objectKind(), equals(PdfObjectType.nullType));
      });
    });

    group('PdfLiteral', () {
      test('creates literal from string', () {
        final lit = CraftPdfLiteral('obj');
        expect(lit.getInternalContent(), isNotNull);
      });

      test('creates literal from bytes', () {
        final bytes = Uint8List.fromList([111, 98, 106]); // "obj"
        final lit = CraftPdfLiteral.fromBytes(bytes);
        expect(lit.getInternalContent(), equals(bytes));
      });

      test('equal literals are equal', () {
        final a = CraftPdfLiteral('stream');
        final b = CraftPdfLiteral('stream');
        expect(a, equals(b));
      });

      test('different literals are not equal', () {
        final a = CraftPdfLiteral('stream');
        final b = CraftPdfLiteral('endstream');
        expect(a, isNot(equals(b)));
      });

      test('getObjectType returns Literal', () {
        expect(CraftPdfLiteral('test').objectKind(),
            equals(PdfObjectType.literal));
      });
    });

    group('PdfArray', () {
      test('creates empty array', () {
        final arr = CraftPdfArray();
        expect(arr.size(), equals(0));
      });

      test('adds elements', () async {
        final arr = CraftPdfArray();
        arr.add(CraftPdfNumber(1.0));
        arr.add(CraftPdfNumber(2.0));
        arr.add(CraftPdfNumber(3.0));
        expect(arr.size(), equals(3));
      });

      test('gets element by index', () async {
        final arr = CraftPdfArray();
        arr.add(CraftPdfNumber(42.0));
        final elem = await arr.get(0);
        expect(elem, isA<CraftPdfNumber>());
        expect((elem as CraftPdfNumber).intValue(), equals(42));
      });

      test('contains element', () async {
        final arr = CraftPdfArray();
        final num = CraftPdfNumber(42.0);
        arr.add(num);
        expect(await arr.containsObject(num), isTrue);
      });

      test('removes element', () async {
        final arr = CraftPdfArray();
        final num = CraftPdfNumber(42.0);
        arr.add(num);
        await arr.remove(num);
        expect(arr.size(), equals(0));
      });

      test('getAsNumber works', () async {
        final arr = CraftPdfArray();
        arr.add(CraftPdfNumber(123.0));
        final num = await arr.numberEntry(0);
        expect(num?.intValue(), equals(123));
      });

      test('getAsString works', () async {
        final arr = CraftPdfArray();
        arr.add(CraftPdfString('hello'));
        final str = await arr.stringEntry(0);
        expect(str?.getValue(), equals('hello'));
      });

      test('getAsDictionary works', () async {
        final arr = CraftPdfArray();
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.type, CraftPdfName.page);
        arr.add(dict);
        final d = await arr.dictionaryEntry(0);
        expect(d, isNotNull);
      });

      test('getObjectType returns Array', () {
        final arr = CraftPdfArray();
        expect(arr.objectKind(), equals(PdfObjectType.array));
      });
    });

    group('PdfDictionary', () {
      test('creates empty dictionary', () {
        final dict = CraftPdfDictionary();
        expect(dict.size(), equals(0));
      });

      test('puts and gets values', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName('Key'), CraftPdfNumber(42.0));
        final value = await dict.get(CraftPdfName('Key'));
        expect(value, isA<CraftPdfNumber>());
        expect((value as CraftPdfNumber).intValue(), equals(42));
      });

      test('contains key', () {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName('Key'), CraftPdfNumber(42.0));
        expect(dict.containsKey(CraftPdfName('Key')), isTrue);
        expect(dict.containsKey(CraftPdfName('Other')), isFalse);
      });

      test('removes key', () {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName('Key'), CraftPdfNumber(42.0));
        dict.remove(CraftPdfName('Key'));
        expect(dict.containsKey(CraftPdfName('Key')), isFalse);
      });

      test('getAsNumber works', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName('Count'), CraftPdfNumber(5.0));
        final num = await dict.numberEntry(CraftPdfName('Count'));
        expect(num?.intValue(), equals(5));
      });

      test('getAsString works', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName('Title'), CraftPdfString('Test Document'));
        final str = await dict.stringEntry(CraftPdfName('Title'));
        expect(str?.getValue(), equals('Test Document'));
      });

      test('getAsName works', () async {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName.type, CraftPdfName.catalog);
        final name = await dict.nameEntry(CraftPdfName.type);
        expect(name, equals(CraftPdfName.catalog));
      });

      test('getAsDictionary works', () async {
        final dict = CraftPdfDictionary();
        final nested = CraftPdfDictionary();
        nested.put(CraftPdfName('Inner'), CraftPdfNumber(1.0));
        dict.put(CraftPdfName('Nested'), nested);
        final d = await dict.dictionaryEntry(CraftPdfName('Nested'));
        expect(d, isNotNull);
      });

      test('getAsArray works', () async {
        final dict = CraftPdfDictionary();
        final arr = CraftPdfArray()..add(CraftPdfNumber(1.0));
        dict.put(CraftPdfName('Kids'), arr);
        final a = await dict.arrayEntry(CraftPdfName('Kids'));
        expect(a, isNotNull);
        expect(a?.size(), equals(1));
      });

      test('keySet returns all keys', () {
        final dict = CraftPdfDictionary();
        dict.put(CraftPdfName('A'), CraftPdfNumber(1.0));
        dict.put(CraftPdfName('B'), CraftPdfNumber(2.0));
        final keys = dict.keySet();
        expect(keys.length, equals(2));
      });

      test('getObjectType returns Dictionary', () {
        final dict = CraftPdfDictionary();
        expect(dict.objectKind(), equals(PdfObjectType.dictionary));
      });
    });
  });
}
