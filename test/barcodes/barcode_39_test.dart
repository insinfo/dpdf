import 'dart:io';

import 'package:dpdf/src/barcodes/barcode_39.dart';
import 'package:dpdf/src/kernel/colors/device_gray.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';

import 'package:test/test.dart';

void main() {
  setUpAll(() => Directory('test/tmp').createSync(recursive: true));
  group('Barcode39 Tests', () {
    test('Barcode39 Standard Test', () async {
      final file = File('test/tmp/barcode_39_test.pdf');
      final writer = CraftPdfWriter(file.openWrite());
      final pdf = await CraftPdfDocument.create(writer);
      final page = await pdf.appendBlankPage();
      final canvas = await CraftPdfCanvas.fromPage(page);

      final barcode = CraftBarcode39(pdf);
      barcode.setCode("CODE39");

      final rect = await barcode.placeBarcode(
          canvas, CraftDeviceGray(0), CraftDeviceGray(0));

      expect(rect.getWidth(), greaterThan(0));
      // Label
      canvas.beginText();
      await canvas.setFontAndSize(pdf.defaultTypeface()!, 12);
      canvas.moveText(100, 500);
      canvas.showText("Code 39 Test");
      canvas.endText();

      await pdf.close();

      expect(file.existsSync(), isTrue);
    });

    test('Barcode39 Extended Test', () async {
      final file = File('test/tmp/barcode_39_ext_test.pdf');
      final writer = CraftPdfWriter(file.openWrite());
      final pdf = await CraftPdfDocument.create(writer);
      final page = await pdf.appendBlankPage();
      final canvas = await CraftPdfCanvas.fromPage(page);

      final barcode = CraftBarcode39(pdf);
      barcode.setExtended(true);
      barcode.setCode("Code 39 Extended");

      final rect = await barcode.placeBarcode(
          canvas, CraftDeviceGray(0), CraftDeviceGray(0));

      expect(rect.getWidth(), greaterThan(0));
      await pdf.close();

      expect(file.existsSync(), isTrue);
    });
  });
}
