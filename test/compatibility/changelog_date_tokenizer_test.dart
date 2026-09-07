import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/pdf_date.dart';
import 'package:dpdf/src/commons/utils/date_time_util.dart';
import 'package:dpdf/dpdf.dart';

void main() {
  test(
      'PDF dates preserve explicit UTC and positive/negative half-hour offsets',
      () {
    final cases = <String, DateTime>{
      'D:20260827143000Z': DateTime.utc(2026, 8, 27, 14, 30),
      "D:20260827143000-03'00'": DateTime.utc(2026, 8, 27, 17, 30),
      "D:20260827143000+05'30'": DateTime.utc(2026, 8, 27, 9),
      'D:20260827003000+0130': DateTime.utc(2026, 8, 26, 23),
      'D:20260827233000-02': DateTime.utc(2026, 8, 28, 1, 30),
    };
    for (final entry in cases.entries) {
      final actual = CraftPdfDate.decode(entry.key);
      expect(actual.isUtc, isTrue, reason: entry.key);
      expect(actual, entry.value, reason: entry.key);
    }
  });
  test(
      'PDF dates without timezone remain local; partial dates default missing fields',
      () {
    expect(CraftPdfDate.decode('D:2026'), DateTime(2026));
    expect(CraftPdfDate.decode('202608'), DateTime(2026, 8));
    expect(CraftPdfDate.decode('D:20260827Z'), DateTime.utc(2026, 8, 27));
  });
  test('Date emitters preserve the instant on roundtrip', () {
    for (final date in [
      DateTime.utc(2026, 8, 27, 14, 30),
      DateTime(2026, 8, 27, 14, 30)
    ]) {
      for (final encoded in [
        CraftPdfDate(date).getValue(),
        CraftDateTimeUtil.formatPdfDate(date)
      ]) {
        expect(CraftPdfDate.decode(encoded).isAtSameMomentAs(date), isTrue);
      }
    }
  });
  test(
      'Malformed PDF dates are input exceptions, not index errors or normalized dates',
      () {
    for (final date in [
      '',
      'D:',
      'D:20',
      'D:20261',
      'D:202613',
      'D:20260230',
      'D:20260827250000Z',
      "D:20260827143000+03'60'",
      'D:20260827143000junk'
    ]) {
      expect(() => CraftPdfDate.decode(date), throwsFormatException,
          reason: date);
    }
  });
  test(
      'Reverse startxref scan includes first block and matches across old block boundaries',
      () {
    for (final position in [0, 15, 1019, 1024, 1500]) {
      final bytes = Uint8List(2600)..fillRange(0, 2600, 32);
      bytes.setRange(position, position + 9, ascii.encode('startxref'));
      final tokenizer = CraftPdfTokenizer(CraftRandomAccessFileOrArray(bytes));
      expect(tokenizer.getStartxref(), position);
    }
  });
  test('Reverse scan selects latest marker without materializing a PDF string',
      () {
    final bytes = Uint8List(2 * 1024 * 1024)..fillRange(0, 2 * 1024 * 1024, 65);
    bytes.setRange(11, 20, ascii.encode('startxref'));
    bytes.setRange(1055, 1064, ascii.encode('startxref'));
    final tokenizer = CraftPdfTokenizer(CraftRandomAccessFileOrArray(bytes));
    expect(tokenizer.getStartxref(), 1055);
  });
  test('Short header reports an exception instead of RangeError', () {
    for (final header in ['%PDF-', '%PDF-1', '%PDF-1.']) {
      final tokenizer = CraftPdfTokenizer(CraftRandomAccessFileOrArray(
          Uint8List.fromList(ascii.encode(header))));
      expect(() => tokenizer.checkPdfHeader(), throwsA(isA<Exception>()));
    }
  });
}
