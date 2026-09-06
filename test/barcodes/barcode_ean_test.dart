import 'dart:io';

import 'package:dpdf/src/barcodes/barcode_ean.dart';
import 'package:dpdf/src/kernel/colors/device_gray.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';

import 'package:test/test.dart';

void main() {
  group('BarcodeEAN Tests', () {
    test('BarcodeEAN13 Basic Test', () async {
      final file = File('test/tmp/barcode_ean13_test.pdf');
      final writer = PdfWriter(file.openWrite());
      final pdf = await PdfDocument.create(writer);
      final page = await pdf.addNewPage();
      final canvas = await PdfCanvas.fromPage(page);

      final barcode = BarcodeEAN(pdf);
      barcode.setCodeType(BarcodeEAN.EAN13);
      barcode.setCode("9780201615963"); // Typical EAN13

      final rect =
          await barcode.placeBarcode(canvas, DeviceGray(0), DeviceGray(0));

      expect(rect.getWidth(), greaterThan(0));
      // Add text label manually just to check position
      canvas.beginText();
      await canvas.setFontAndSize(pdf.getDefaultFont()!, 12);
      canvas.moveText(100, 500);
      canvas.showText("EAN13 Barcode Test");
      canvas.endText();

      await pdf.close();

      expect(file.existsSync(), isTrue);
    });

    test('BarcodeEAN8 Basic Test', () async {
      final file = File('test/tmp/barcode_ean8_test.pdf');
      final writer = PdfWriter(file.openWrite());
      final pdf = await PdfDocument.create(writer);
      final page = await pdf.addNewPage();
      final canvas = await PdfCanvas.fromPage(page);

      final barcode = BarcodeEAN(pdf);
      barcode.setCodeType(BarcodeEAN.EAN8);
      barcode.setCode("12345670"); // Typical EAN8

      final rect =
          await barcode.placeBarcode(canvas, DeviceGray(0), DeviceGray(0));

      expect(rect.getWidth(), greaterThan(0));
      await pdf.close();

      expect(file.existsSync(), isTrue);
    });
  });
}
