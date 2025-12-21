import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:itext/itext.dart';

/// Creates a minimal valid PDF for testing
Uint8List createMinimalPdf() {
  // A minimal PDF 1.4 document with one page
  // Each line must have correct byte offsets for the xref table
  final buffer = StringBuffer();

  // PDF header (9 bytes: %PDF-1.4\n)
  buffer.write('%PDF-1.4\n');

  // Object 1: Catalog (starts at offset 9)
  final obj1Start = buffer.length; // 9
  buffer.write('1 0 obj\n');
  buffer.write('<< /Type /Catalog /Pages 2 0 R >>\n');
  buffer.write('endobj\n');

  // Object 2: Pages (starts at offset after obj1)
  final obj2Start = buffer.length; // ~60
  buffer.write('2 0 obj\n');
  buffer.write('<< /Type /Pages /Kids [3 0 R] /Count 1 >>\n');
  buffer.write('endobj\n');

  // Object 3: Page (starts at offset after obj2)
  final obj3Start = buffer.length; // ~118
  buffer.write('3 0 obj\n');
  buffer.write('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>\n');
  buffer.write('endobj\n');

  // xref table (starts at offset after obj3)
  final xrefStart = buffer.length;
  buffer.write('xref\n');
  buffer.write('0 4\n');
  // Format: 10-digit offset, space, 5-digit gen, space, f/n, space+newline (20 chars)
  buffer.write('0000000000 65535 f \n');
  buffer.write('${obj1Start.toString().padLeft(10, '0')} 00000 n \n');
  buffer.write('${obj2Start.toString().padLeft(10, '0')} 00000 n \n');
  buffer.write('${obj3Start.toString().padLeft(10, '0')} 00000 n \n');

  // Trailer
  buffer.write('trailer\n');
  buffer.write('<< /Size 4 /Root 1 0 R >>\n');
  buffer.write('startxref\n');
  buffer.write('$xrefStart\n');
  buffer.write('%%EOF\n');

  return Uint8List.fromList(utf8.encode(buffer.toString()));
}

/// Creates a PDF with info dictionary
Uint8List createPdfWithInfo() {
  final buffer = StringBuffer();

  // PDF header
  buffer.write('%PDF-1.4\n');

  // Object 1: Catalog
  final obj1Start = buffer.length;
  buffer.write('1 0 obj\n');
  buffer.write('<< /Type /Catalog /Pages 2 0 R >>\n');
  buffer.write('endobj\n');

  // Object 2: Pages
  final obj2Start = buffer.length;
  buffer.write('2 0 obj\n');
  buffer.write('<< /Type /Pages /Kids [3 0 R] /Count 1 >>\n');
  buffer.write('endobj\n');

  // Object 3: Page
  final obj3Start = buffer.length;
  buffer.write('3 0 obj\n');
  buffer.write('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>\n');
  buffer.write('endobj\n');

  // Object 4: Info
  final obj4Start = buffer.length;
  buffer.write('4 0 obj\n');
  buffer.write('<< /Title (Test Document) /Author (iText Dart) >>\n');
  buffer.write('endobj\n');

  // xref table
  final xrefStart = buffer.length;
  buffer.write('xref\n');
  buffer.write('0 5\n');
  buffer.write('0000000000 65535 f \n');
  buffer.write('${obj1Start.toString().padLeft(10, '0')} 00000 n \n');
  buffer.write('${obj2Start.toString().padLeft(10, '0')} 00000 n \n');
  buffer.write('${obj3Start.toString().padLeft(10, '0')} 00000 n \n');
  buffer.write('${obj4Start.toString().padLeft(10, '0')} 00000 n \n');

  // Trailer
  buffer.write('trailer\n');
  buffer.write('<< /Size 5 /Root 1 0 R /Info 4 0 R >>\n');
  buffer.write('startxref\n');
  buffer.write('$xrefStart\n');
  buffer.write('%%EOF\n');

  return Uint8List.fromList(utf8.encode(buffer.toString()));
}

void main() {
  group('PdfReader', () {
    group('Header', () {
      test('reads PDF version from header', () {
        final reader = PdfReader.fromBytes(createMinimalPdf());
        reader.read();

        // PDF version is extracted from "PDF-1.4" -> "1.4"
        expect(reader.pdfVersion, contains('1.4'));
        reader.close();
      });
    });

    group('Xref Table', () {
      test('reads xref entries', () {
        final reader = PdfReader.fromBytes(createMinimalPdf());
        reader.read();

        // Should have 4 objects (0-3)
        expect(reader.xref.size(), equals(4));

        // Object 0 is free
        final ref0 = reader.xref.get(0);
        expect(ref0, isNotNull);
        expect(ref0!.isFree(), isTrue);

        // Objects 1-3 are in use
        final ref1 = reader.xref.get(1);
        expect(ref1, isNotNull);
        expect(ref1!.isFree(), isFalse);
        expect(ref1.getOffset(), greaterThan(0));

        reader.close();
      });
    });

    group('Trailer', () {
      test('reads trailer dictionary', () {
        final reader = PdfReader.fromBytes(createMinimalPdf());
        reader.read();

        expect(reader.trailer, isNotNull);
        expect(reader.trailer!.getAsInt(PdfName.size), equals(4));

        final root = reader.trailer!.get(PdfName.root);
        expect(root, isA<PdfIndirectReference>());

        reader.close();
      });
    });

    group('Catalog', () {
      test('reads catalog dictionary', () {
        final reader = PdfReader.fromBytes(createMinimalPdf());
        reader.read();

        final catalog = reader.getCatalog();
        expect(catalog, isNotNull);
        expect(catalog!.getAsName(PdfName.type), equals(PdfName.catalog));

        reader.close();
      });
    });

    group('Pages', () {
      test('gets number of pages', () {
        final reader = PdfReader.fromBytes(createMinimalPdf());
        reader.read();

        final numPages = reader.getNumberOfPages();
        expect(numPages, equals(1));

        reader.close();
      });
    });

    group('Info Dictionary', () {
      test('reads info dictionary', () {
        final reader = PdfReader.fromBytes(createPdfWithInfo());
        reader.read();

        final info = reader.getInfo();
        expect(info, isNotNull);

        final title = info!.getAsString(PdfName('Title'));
        expect(title?.getValue(), equals('Test Document'));

        final author = info.getAsString(PdfName('Author'));
        expect(author?.getValue(), equals('iText Dart'));

        reader.close();
      });
    });

    group('Object Reading', () {
      test('reads individual objects', () {
        final reader = PdfReader.fromBytes(createMinimalPdf());
        reader.read();

        // Read object 1 (Catalog)
        final obj1 = reader.readObject(1);
        expect(obj1, isA<PdfDictionary>());

        final dict1 = obj1 as PdfDictionary;
        expect(dict1.getAsName(PdfName.type), equals(PdfName.catalog));

        // Read object 2 (Pages)
        final obj2 = reader.readObject(2);
        expect(obj2, isA<PdfDictionary>());

        final dict2 = obj2 as PdfDictionary;
        expect(dict2.getAsName(PdfName.type), equals(PdfName.pages));
        expect(dict2.getAsInt(PdfName.count), equals(1));

        reader.close();
      });

      test('returns null for free object', () {
        final reader = PdfReader.fromBytes(createMinimalPdf());
        reader.read();

        // Object 0 is always free
        final obj0 = reader.readObject(0);
        expect(obj0, isNull);

        reader.close();
      });

      test('returns null for non-existent object', () {
        final reader = PdfReader.fromBytes(createMinimalPdf());
        reader.read();

        // Object 100 doesn't exist
        final obj100 = reader.readObject(100);
        expect(obj100, isNull);

        reader.close();
      });
    });

    group('Encryption', () {
      test('detects unencrypted document', () {
        final reader = PdfReader.fromBytes(createMinimalPdf());
        reader.read();

        expect(reader.encrypted, isFalse);

        reader.close();
      });
    });
  });
}
