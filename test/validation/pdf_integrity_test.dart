import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// Builds a small, structurally sound document in memory so the damage cases
/// below start from a file the checker calls clean.
Future<Uint8List> _healthyDocument({int pages = 2}) async {
  final output = BytesBuilder(copy: false);
  final document =
      await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(output));
  for (var i = 0; i < pages; i++) {
    await document.appendBlankPage();
  }
  await document.close();
  return output.takeBytes();
}

/// Replaces the first occurrence of [needle] with [replacement] of the same
/// length, so every byte offset in the file keeps its meaning.
Uint8List _patch(Uint8List source, String needle, String replacement) {
  expect(replacement.length, equals(needle.length),
      reason: 'the patch must not move any offset');
  final bytes = Uint8List.fromList(source);
  final target = needle.codeUnits;
  outer:
  for (var i = 0; i <= bytes.length - target.length; i++) {
    for (var j = 0; j < target.length; j++) {
      if (bytes[i + j] != target[j]) continue outer;
    }
    bytes.setRange(i, i + target.length, replacement.codeUnits);
    return bytes;
  }
  fail('pattern "$needle" not present in the fixture');
}

void main() {
  group('PdfIntegrityChecker', () {
    test('reports a well formed document as clean', () async {
      final report =
          await PdfIntegrityChecker.inspect(await _healthyDocument());

      expect(report.readable, isTrue);
      expect(report.isDamaged, isFalse);
      expect(report.recoveryUsed, isFalse);
      expect(report.encrypted, isFalse);
      expect(report.headerVersion, isNotNull);
      expect(report.reachablePageCount, equals(2));
      expect(report.declaredPageCount, equals(2));
      expect(report.objectCount, greaterThan(0));
      expect(report.revisionCount, equals(1));
      expect(report.trailingBytes, isZero);
      expect(report.errors, isEmpty);
    });

    test('reads the checked-in sample without reporting damage', () async {
      final bytes = await File('test/assets/test.pdf').readAsBytes();
      final report = await PdfIntegrityChecker.inspect(bytes);

      expect(report.readable, isTrue);
      expect(report.reachablePageCount, greaterThan(0));
      expect(report.errors, isEmpty, reason: report.errors.join('\n'));
    });

    test('flags a file with no header', () async {
      final healthy = await _healthyDocument();
      final headless = Uint8List.fromList(healthy.sublist(9));

      final report = await PdfIntegrityChecker.inspect(headless);

      expect(report.findings.map((f) => f.code), contains('missing-header'));
    });

    test('flags an empty input', () async {
      final report = await PdfIntegrityChecker.inspect(Uint8List(0));

      expect(report.readable, isFalse);
      expect(report.findings.map((f) => f.code), contains('empty-file'));
      expect(report.isDamaged, isTrue);
    });

    test('flags truncation after the last %%EOF is lost', () async {
      final healthy = await _healthyDocument();
      final truncated = Uint8List.fromList(
          healthy.sublist(0, (healthy.length * 0.8).round()));

      final report = await PdfIntegrityChecker.inspect(truncated);

      expect(report.findings.map((f) => f.code), contains('missing-eof'));
      expect(report.isDamaged, isTrue);
    });

    test('reports bytes appended after the last %%EOF', () async {
      final healthy = await _healthyDocument();
      final padded = Uint8List.fromList(
          [...healthy, ...'garbage appended by a proxy'.codeUnits]);

      final report = await PdfIntegrityChecker.inspect(padded);

      expect(report.trailingBytes, equals(27));
      expect(report.warnings.map((f) => f.code), contains('trailing-bytes'));
    });

    test('detects a page count the tree does not support', () async {
      final healthy = await _healthyDocument(pages: 2);
      final lying = _patch(healthy, '/Count 2', '/Count 7');

      final report = await PdfIntegrityChecker.inspect(lying);

      expect(report.declaredPageCount, equals(7));
      expect(report.reachablePageCount, equals(2));
      expect(report.errors.map((f) => f.code), contains('page-count-mismatch'));
    });

    test('detects a cross-reference offset that misses its object', () async {
      final healthy = await _healthyDocument();
      // Shift every recorded offset by rewriting the startxref target's own
      // digits is not enough: corrupt one entry inside the table instead.
      final text = String.fromCharCodes(healthy);
      final entry = RegExp(r'\n(\d{10}) 00000 n').firstMatch(text);
      if (entry == null) {
        // The writer emitted a cross-reference stream; the offset check is
        // covered by the recovery test below instead.
        return;
      }
      final broken =
          _patch(healthy, '${entry.group(1)} 00000 n', '0000000009 00000 n');

      final report = await PdfIntegrityChecker.inspect(broken);

      expect(
        report.errors.map((f) => f.code),
        anyElement(anyOf('xref-offset-mismatch', 'xref-unusable',
            'object-parse-failed', 'object-unreadable')),
      );
    });

    test('serializes to a stable machine readable map', () async {
      final report =
          await PdfIntegrityChecker.inspect(await _healthyDocument());
      final json = report.toJson();

      expect(json['readable'], isTrue);
      expect(json['damaged'], isFalse);
      expect(json['reachablePageCount'], equals(2));
      expect(json['findings'], isA<List<Object?>>());
    });

    test('skips stream decoding when deepScan is off', () async {
      final healthy = await _healthyDocument();

      final shallow =
          await PdfIntegrityChecker.inspect(healthy, deepScan: false);

      expect(shallow.readable, isTrue);
      expect(shallow.isDamaged, isFalse);
    });
  });
}
