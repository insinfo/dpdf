import 'dart:typed_data';

import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_page.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/viewer/pdf_measure.dart';
import 'package:test/test.dart';

/// Builds the architectural example of 12.9: a rectilinear scale where a
/// quarter inch in user space is one foot in the real world.
PdfMeasure architecturalScale() {
  final feet = PdfNumberFormat.create('ft', 1 / 18);
  final inches = PdfNumberFormat.create('in', 12);
  final squareFeet = PdfNumberFormat.create('sq ft', 1);
  return PdfMeasure.createRectilinear()
    ..setScaleRatio('1/4 in = 1 ft')
    ..setNumberFormats(PdfMeasure.xAxis, [feet, inches])
    ..setNumberFormats(PdfMeasure.distance, [feet, inches])
    ..setNumberFormats(PdfMeasure.area, [squareFeet]);
}

Future<PdfPage> roundtrip(Future<void> Function(PdfPage) build) async {
  final bytes = BytesBuilder();
  final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
  final page = await doc.appendBlankPage();
  await build(page);
  await doc.close();

  final reopened = await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
  addTearDown(reopened.close);
  return (await reopened.firstPage())!;
}

void main() {
  group('measurement properties (ISO 32000-1:2008, 12.9, Tables 260 to 263)',
      () {
    test('a viewport with a rectilinear measure survives a roundtrip',
        () async {
      final page = await roundtrip((page) async {
        await page.addViewport(PdfViewport.create(Rectangle(36, 36, 300, 400))
          ..setName('Floor plan')
          ..setMeasure(architecturalScale()));
      });

      final viewports = await page.getViewports();
      expect(viewports, hasLength(1));
      final viewport = viewports.single;
      expect(await viewport.pdfRepresentation().nameEntry(PdfName.type),
          PdfViewport.viewport);
      expect(await viewport.getName(), 'Floor plan');
      final bounds = (await viewport.getBounds())!;
      expect(bounds.getLeft(), 36);
      expect(bounds.getRight(), 336);

      final measure = (await viewport.getMeasure())!;
      expect(await measure.getSubtype(), PdfMeasure.rectilinear);
      expect(await measure.getScaleRatio(), '1/4 in = 1 ft');
      final xFormats = await measure.getNumberFormats(PdfMeasure.xAxis);
      expect(xFormats, hasLength(2));
      expect(await xFormats[0].getUnit(), 'ft');
      expect(await xFormats[1].getUnit(), 'in');
      expect(await xFormats[1].getConversionFactor(), 12);
      await viewport.validate();
    });

    test('number format defaults follow Table 263', () async {
      final page = await roundtrip((page) async {
        await page.addViewport(PdfViewport.create(Rectangle(0, 0, 100, 100))
          ..setMeasure(architecturalScale()));
      });

      final measure = (await (await page.getViewports()).single.getMeasure())!;
      final format = (await measure.getNumberFormats(PdfMeasure.xAxis)).first;
      expect(await format.getFractionDisplay(), PdfFractionDisplay.decimal);
      expect(await format.getPrecision(), 100);
      expect(await format.getFixedDenominator(), isFalse);
      expect(await format.getThousandsSeparator(), ',');
      expect(await format.getDecimalSeparator(), '.');
      expect(await format.getLabelPrefix(), ' ');
      expect(await format.getLabelSuffix(), ' ');
      expect(await format.getLabelPosition(), PdfLabelPosition.suffix);
    });

    test('a fractional display defaults to a denominator of 16', () async {
      final format = PdfNumberFormat.create('in', 12)
        ..setFractionDisplay(PdfFractionDisplay.fraction);
      expect(await format.getPrecision(), 16);

      await format.setPrecision(8);
      expect(await format.getPrecision(), 8);
    });

    test('a decimal precision shall be a multiple of ten', () async {
      final format = PdfNumberFormat.create('ft', 1);
      await format.setPrecision(1000);
      expect(await format.getPrecision(), 1000);
      expect(() => format.setPrecision(25), throwsA(isA<PdfException>()));
      expect(() => format.setPrecision(0), throwsA(isA<PdfException>()));
    });

    test('an empty unit label or a non positive factor is rejected', () {
      expect(() => PdfNumberFormat.create('', 1), throwsA(isA<PdfException>()));
      expect(
          () => PdfNumberFormat.create('ft', 0), throwsA(isA<PdfException>()));
      expect(
          () => PdfNumberFormat.create('ft', -3), throwsA(isA<PdfException>()));
    });

    test('separators and label position survive a roundtrip', () async {
      final page = await roundtrip((page) async {
        final measure = architecturalScale();
        final metres = PdfNumberFormat.create('m', 1)
          ..setThousandsSeparator('')
          ..setDecimalSeparator(',')
          ..setLabelPrefix('')
          ..setLabelSuffix('')
          ..setLabelPosition(PdfLabelPosition.prefix)
          ..setFixedDenominator(true);
        measure.setNumberFormats(PdfMeasure.yAxis, [metres]);
        measure.setCyx(2.5);
        measure.setOrigin(10, 20);
        await page.addViewport(
            PdfViewport.create(Rectangle(0, 0, 500, 500))..setMeasure(measure));
      });

      final measure = (await (await page.getViewports()).single.getMeasure())!;
      final metres = (await measure.getNumberFormats(PdfMeasure.yAxis)).single;
      expect(await metres.getThousandsSeparator(), '');
      expect(await metres.getDecimalSeparator(), ',');
      expect(await metres.getLabelPrefix(), '');
      expect(await metres.getLabelSuffix(), '');
      expect(await metres.getLabelPosition(), PdfLabelPosition.prefix);
      expect(await metres.getFixedDenominator(), isTrue);
      expect(await measure.getCyx(), 2.5);
      expect(await measure.getOrigin(), [10, 20]);
    });

    test('overlapping viewports resolve from the last one backwards', () async {
      final page = await roundtrip((page) async {
        await page.addViewport(
            PdfViewport.create(Rectangle(0, 0, 400, 400))..setName('under'));
        await page.addViewport(
            PdfViewport.create(Rectangle(100, 100, 100, 100))..setName('over'));
      });

      // The point lies in both, so 12.9 picks the later entry.
      expect(await (await page.viewportAt(150, 150))!.getName(), 'over');
      // Only the first covers this one.
      expect(await (await page.viewportAt(50, 50))!.getName(), 'under');
      // Outside every viewport.
      expect(await page.viewportAt(900, 900), isNull);
    });

    test('a page without /VP reports no viewports', () async {
      final page = await roundtrip((page) async {});
      expect(await page.getViewports(), isEmpty);
      expect(await page.viewportAt(10, 10), isNull);
    });

    test('a degenerate /BBox is rejected', () {
      expect(() => PdfViewport.create(Rectangle(10, 10, 0, 50)),
          throwsA(isA<PdfException>()));
      expect(() => PdfViewport.create(Rectangle(10, 10, 50, -5)),
          throwsA(isA<PdfException>()));
    });

    test('a viewport without /BBox fails validation', () async {
      final viewport = PdfViewport(PdfDictionary());
      expect(viewport.validate, throwsA(isA<PdfException>()));
      expect(await viewport.contains(1, 1), isFalse);
    });

    test('a rectilinear measure without /R, /X, /D or /A fails validation',
        () async {
      for (final missing in [
        PdfMeasure.scaleRatio,
        PdfMeasure.xAxis,
        PdfMeasure.distance,
        PdfMeasure.area,
      ]) {
        final measure = architecturalScale();
        measure.pdfRepresentation().remove(missing);
        expect(measure.validate, throwsA(isA<PdfException>()),
            reason: missing.getValue());
      }
    });

    test('an empty number format array is rejected', () async {
      final measure = architecturalScale();
      expect(() => measure.setNumberFormats(PdfMeasure.angle, []),
          throwsA(isA<PdfException>()));

      // A foreign writer could still leave one empty, which validate catches.
      measure.pdfRepresentation().put(PdfMeasure.angle, PdfArray());
      expect(measure.validate, throwsA(isA<PdfException>()));
    });

    test('a number format array holding an incomplete entry is rejected',
        () async {
      final measure = architecturalScale();
      final incomplete = PdfArray();
      incomplete.add(PdfDictionary());
      measure.pdfRepresentation().put(PdfMeasure.slope, incomplete);
      expect(measure.validate, throwsA(isA<PdfException>()));
    });

    test('an empty scale ratio is rejected', () {
      expect(() => PdfMeasure.createRectilinear().setScaleRatio(''),
          throwsA(isA<PdfException>()));
    });

    test('a viewport carrying an invalid measure is refused by the page',
        () async {
      final bytes = BytesBuilder();
      final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await doc.appendBlankPage();

      final broken = architecturalScale();
      broken.pdfRepresentation().remove(PdfMeasure.area);
      final viewport = PdfViewport.create(Rectangle(0, 0, 10, 10))
        ..setMeasure(broken);

      expect(() => page.addViewport(viewport), throwsA(isA<PdfException>()));
      expect(await page.getViewports(), isEmpty);
      await doc.close();
    });

    test('a measure of another subtype skips the Table 262 checks', () async {
      final measure = PdfMeasure(PdfDictionary());
      measure
          .pdfRepresentation()
          .put(PdfMeasure.subtype, PdfName.intern('GEO'));
      // Table 262 describes the rectilinear subtype only, so nothing is
      // required here.
      await measure.validate();
      expect(await measure.getSubtype(), PdfName.intern('GEO'));
    });

    test('/PtData is carried through unchanged', () async {
      final page = await roundtrip((page) async {
        final data = PdfDictionary();
        data.put(PdfName.intern('Subtype'), PdfName.intern('Cloud'));
        await page.addViewport(
            PdfViewport.create(Rectangle(0, 0, 50, 50))..setPointData(data));
      });

      final restored = await (await page.getViewports()).single.getPointData();
      expect(restored, isA<PdfDictionary>());
      expect(
          await (restored as PdfDictionary)
              .nameEntry(PdfName.intern('Subtype')),
          PdfName.intern('Cloud'));
    });
  });
}
