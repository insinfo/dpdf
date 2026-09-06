import 'dart:io';

import 'package:pdfcraft/src/barcodes/barcode_ean.dart';
import 'package:pdfcraft/src/kernel/colors/device_gray.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_writer.dart';
import 'package:pdfcraft/src/kernel/pdf/canvas/pdf_canvas.dart';

import 'package:test/test.dart';

void main() {
  setUpAll(() => Directory('test/tmp').createSync(recursive: true));
  group('BarcodeEAN Tests', () {
    test('BarcodeEAN13 Basic Test', () async {
      final file = File('test/tmp/barcode_ean13_test.pdf');
      final writer = CraftPdfWriter(file.openWrite());
      final pdf = await CraftPdfDocument.create(writer);
      final page = await pdf.appendBlankPage();
      final canvas = await CraftPdfCanvas.fromPage(page);

      final barcode = CraftBarcodeEAN(pdf);
      barcode.setCodeType(CraftBarcodeEAN.EAN13);
      barcode.setCode("9780201615963"); // Typical EAN13

      final rect = await barcode.placeBarcode(
          canvas, CraftDeviceGray(0), CraftDeviceGray(0));

      expect(rect.getWidth(), greaterThan(0));
      // Add text label manually just to check position
      canvas.beginText();
      await canvas.setFontAndSize(pdf.defaultTypeface()!, 12);
      canvas.moveText(100, 500);
      canvas.showText("EAN13 Barcode Test");
      canvas.endText();

      await pdf.close();

      expect(file.existsSync(), isTrue);
    });

    test('BarcodeEAN8 Basic Test', () async {
      final file = File('test/tmp/barcode_ean8_test.pdf');
      final writer = CraftPdfWriter(file.openWrite());
      final pdf = await CraftPdfDocument.create(writer);
      final page = await pdf.appendBlankPage();
      final canvas = await CraftPdfCanvas.fromPage(page);

      final barcode = CraftBarcodeEAN(pdf);
      barcode.setCodeType(CraftBarcodeEAN.EAN8);
      barcode.setCode("12345670"); // Typical EAN8

      final rect = await barcode.placeBarcode(
          canvas, CraftDeviceGray(0), CraftDeviceGray(0));

      expect(rect.getWidth(), greaterThan(0));
      await pdf.close();

      expect(file.existsSync(), isTrue);
    });
  });
}
