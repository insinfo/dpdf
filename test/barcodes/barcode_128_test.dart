import 'dart:io';

import 'package:pdfcraft/src/barcodes/barcode_128.dart';
import 'package:pdfcraft/src/kernel/colors/device_gray.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_writer.dart';
import 'package:pdfcraft/src/kernel/pdf/canvas/pdf_canvas.dart';

import 'package:test/test.dart';

void main() {
  setUpAll(() => Directory('test/tmp').createSync(recursive: true));
  group('Barcode128 Tests', () {
    test('Barcode128 Basic Test', () async {
      final file = File('test/tmp/barcode_128_test.pdf');
      final writer = CraftPdfWriter(file.openWrite());
      final pdf = await CraftPdfDocument.create(writer);
      final page = await pdf.appendBlankPage();
      final canvas = await CraftPdfCanvas.fromPage(page);

      final barcode = CraftBarcode128(pdf);
      barcode.setCode("123456789");
      barcode.setCodeType(CraftBarcode128.CODE128); // Standard

      final rect = await barcode.placeBarcode(
          canvas, CraftDeviceGray(0), CraftDeviceGray(0));

      expect(rect.getWidth(), greaterThan(0));
      // Add text label manually just to check position
      canvas.beginText();
      await canvas.setFontAndSize(pdf.defaultTypeface()!, 12);
      canvas.moveText(100, 500);
      canvas.showText("Hello Barcode 128");
      canvas.endText();

      await pdf.close();

      expect(file.existsSync(), isTrue);
    });
  });
}
