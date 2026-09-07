import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

PdfConformanceFinding _finding(String code, [int? page]) =>
    PdfConformanceFinding(
      code,
      PdfConformanceSeverity.violation,
      'a font is not embedded',
      clause: 'ISO 19005-2:6.3.4',
      page: page,
    );

void main() {
  group('FindingSink', () {
    test('keeps every occurrence below the limit', () {
      final sink = FindingSink(perCodeLimit: 5);
      for (var i = 1; i <= 3; i++) {
        sink.add(_finding('font-not-embedded', i));
      }

      final result = sink.build();
      expect(result, hasLength(3));
      expect(result.every((f) => f.code == 'font-not-embedded'), isTrue);
    });

    test('caps a repeated rule and says how many there were', () {
      final sink = FindingSink(perCodeLimit: 4);
      for (var i = 1; i <= 30; i++) {
        sink.add(_finding('font-not-embedded', i));
      }

      final result = sink.build();
      expect(result.where((f) => f.code == 'font-not-embedded'), hasLength(4));

      final summary =
          result.singleWhere((f) => f.code == 'font-not-embedded-repeated');
      expect(summary.severity, equals(PdfConformanceSeverity.info));
      expect(summary.message, contains('30 times'));
      expect(summary.clause, equals('ISO 19005-2:6.3.4'));
    });

    test('caps each rule independently', () {
      final sink = FindingSink(perCodeLimit: 2);
      for (var i = 0; i < 5; i++) {
        sink.add(_finding('font-not-embedded', i));
      }
      sink.add(_finding('encrypted'));

      final result = sink.build();
      expect(result.where((f) => f.code == 'font-not-embedded'), hasLength(2));
      expect(result.where((f) => f.code == 'encrypted'), hasLength(1));
      expect(result.where((f) => f.code.endsWith('-repeated')), hasLength(1));
    });

    test('reports which rules it has seen', () {
      final sink = FindingSink()..add(_finding('encrypted'));

      expect(sink.contains('encrypted'), isTrue);
      expect(sink.contains('not-marked'), isFalse);
    });

    test('builds an unmodifiable list', () {
      final sink = FindingSink()..add(_finding('encrypted'));

      expect(() => sink.build().add(_finding('other')), throwsUnsupportedError);
    });

    test('builds nothing when nothing was added', () {
      expect(FindingSink().build(), isEmpty);
    });
  });
}
