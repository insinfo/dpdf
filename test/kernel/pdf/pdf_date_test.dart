import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/pdf_date.dart';

void main() {
  group('PdfDate', () {
    test('creates from DateTime', () {
      final d = DateTime(2024, 12, 25, 10, 30, 45);
      final pdfDate = PdfDate(d);
      expectLater(pdfDate.getValue(), startsWith('D:20241225103045'));
    });

    test('creates now', () {
      final pdfDate = PdfDate.now();
      expect(pdfDate.getValue(), startsWith('D:'));
    });

    test('getW3CDate converts correctly', () {
      final w3c = PdfDate.getW3CDateFromString('D:20241225103045+03\'00\'');
      expect(w3c, equals('2024-12-25T10:30:45+03:00'));
    });

    test('getW3CDate handles Z timezone', () {
      final w3c = PdfDate.getW3CDateFromString('D:20241225103045Z');
      expect(w3c, equals('2024-12-25T10:30:45Z'));
    });

    test('getW3CDate handles short date', () {
      final w3c = PdfDate.getW3CDateFromString('D:2024');
      expect(w3c, equals('2024'));
    });

    test('getW3CDate handles date only', () {
      final w3c = PdfDate.getW3CDateFromString('D:20241225');
      expect(w3c, equals('2024-12-25'));
    });

    test('decode parses full date', () {
      final d = PdfDate.decode('D:20241225103045Z');
      expect(d.year, equals(2024));
      expect(d.month, equals(12));
      expect(d.day, equals(25));
    });

    test('decode parses date without timezone', () {
      final d = PdfDate.decode('D:20240601120000');
      expect(d.year, equals(2024));
      expect(d.month, equals(6));
      expect(d.day, equals(1));
      expect(d.hour, equals(12));
    });

    test('decode parses minimal date', () {
      final d = PdfDate.decode('D:2024');
      expect(d.year, equals(2024));
      expect(d.month, equals(1));
      expect(d.day, equals(1));
    });
  });
}
