import 'dart:io';

import 'package:dpdf/src/barcodes/barcode_128.dart';
import 'package:dpdf/src/kernel/colors/device_gray.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';

import 'package:test/test.dart';

void main() {
  group('Barcode128 Tests', () {
    test('Barcode128 Basic Test', () async {
      final file = File('test/tmp/barcode_128_test.pdf');
      final writer = PdfWriter(file.openWrite());
      final pdf = await PdfDocument.create(writer);
      final page = await pdf.addNewPage();
      final canvas = await PdfCanvas.fromPage(page);

      final barcode = Barcode128(pdf);
      barcode.setCode("123456789");
      barcode.setCodeType(Barcode128.CODE128); // Standard

      final rect =
          await barcode.placeBarcode(canvas, DeviceGray(0), DeviceGray(0));

      expect(rect.getWidth(), greaterThan(0));
      // Add text label manually just to check position
      canvas.beginText();
      await canvas.setFontAndSize(pdf.getDefaultFont()!, 12);
      canvas.moveText(100, 500);
      canvas.showText("Hello Barcode 128");
      canvas.endText();

      await pdf.close();

      expect(file.existsSync(), isTrue);
    });
  });
}
