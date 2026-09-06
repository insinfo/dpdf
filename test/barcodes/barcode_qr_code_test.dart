import 'dart:io';

import 'package:pdfcraft/src/barcodes/barcode_qr_code.dart';
import 'package:pdfcraft/src/barcodes/qrcode/encode_hint_type.dart';
import 'package:pdfcraft/src/kernel/colors/device_gray.dart';
import 'package:pdfcraft/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_writer.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => Directory('test/tmp').createSync(recursive: true));
  group('BarcodeQRCode Tests', () {
    test('BarcodeQRCode Basic Test', () async {
      final file = File('test/tmp/barcode_qr_code_test.pdf');
      final writer = CraftPdfWriter(file.openWrite());
      final pdf = await CraftPdfDocument.create(writer);
      final page = await pdf.appendBlankPage();
      final canvas = await CraftPdfCanvas.fromPage(page);

      final barcode = CraftBarcodeQRCode("https://pdfcraftpdf.com");

      // Test basic getters
      expect(barcode.getCode(), equals("https://pdfcraftpdf.com"));

      final rect = barcode.placeBarcode(canvas, CraftDeviceGray(0));

      expect(rect.getWidth(), greaterThan(0));
      // Add text label
      canvas.beginText();
      await canvas.setFontAndSize(pdf.defaultTypeface()!, 12);
      canvas.moveText(100, 500);
      canvas.showText("Hello QR Code");
      canvas.endText();

      await pdf.close();

      expect(file.existsSync(), isTrue);
    });

    test('BarcodeQRCode Hints Test', () async {
      final hints = {CraftEncodeHintType.CHARACTER_SET: "UTF-8"};
      final barcode = CraftBarcodeQRCode("Test Hints", hints);
      expect(barcode.getHints(), equals(hints));

      // Sizing check
      final size = barcode.getBarcodeSize();
      expect(size, isNotNull);
      expect(size!.getWidth(), greaterThan(0));
    });

    test('BarcodeQRCode CreateFormXObject Test', () async {
      final file = File('test/tmp/barcode_qr_code_xobject_test.pdf');
      final writer = CraftPdfWriter(file.openWrite());
      final pdf = await CraftPdfDocument.create(writer);
      final page = await pdf.appendBlankPage();
      final canvas = await CraftPdfCanvas.fromPage(page);

      final barcode = CraftBarcodeQRCode("XObject Test");
      final xObject = await barcode.createFormXObject(pdf, CraftDeviceGray(0));

      // Draw XObject on canvas
      await canvas.addXObjectWithTransformationMatrix(
          xObject.pdfRepresentation(), 1, 0, 0, 1, 50, 600);

      await pdf.close();
      expect(file.existsSync(), isTrue);
    });
  });
}
