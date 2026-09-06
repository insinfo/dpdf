import 'dart:io';

import 'package:dpdf/src/barcodes/barcode_qr_code.dart';
import 'package:dpdf/src/barcodes/qrcode/encode_hint_type.dart';
import 'package:dpdf/src/kernel/colors/device_gray.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:test/test.dart';

void main() {
  group('BarcodeQRCode Tests', () {
    test('BarcodeQRCode Basic Test', () async {
      final file = File('test/tmp/barcode_qr_code_test.pdf');
      final writer = PdfWriter(file.openWrite());
      final pdf = await PdfDocument.create(writer);
      final page = await pdf.addNewPage();
      final canvas = await PdfCanvas.fromPage(page);

      final barcode = BarcodeQRCode("https://pdfcraftpdf.com");

      // Test basic getters
      expect(barcode.getCode(), equals("https://pdfcraftpdf.com"));

      final rect = barcode.placeBarcode(canvas, DeviceGray(0));

      expect(rect.getWidth(), greaterThan(0));
      // Add text label
      canvas.beginText();
      await canvas.setFontAndSize(pdf.getDefaultFont()!, 12);
      canvas.moveText(100, 500);
      canvas.showText("Hello QR Code");
      canvas.endText();

      await pdf.close();

      expect(file.existsSync(), isTrue);
    });

    test('BarcodeQRCode Hints Test', () async {
      final hints = {EncodeHintType.CHARACTER_SET: "UTF-8"};
      final barcode = BarcodeQRCode("Test Hints", hints);
      expect(barcode.getHints(), equals(hints));

      // Sizing check
      final size = barcode.getBarcodeSize();
      expect(size, isNotNull);
      expect(size!.getWidth(), greaterThan(0));
    });

    test('BarcodeQRCode CreateFormXObject Test', () async {
      final file = File('test/tmp/barcode_qr_code_xobject_test.pdf');
      final writer = PdfWriter(file.openWrite());
      final pdf = await PdfDocument.create(writer);
      final page = await pdf.addNewPage();
      final canvas = await PdfCanvas.fromPage(page);

      final barcode = BarcodeQRCode("XObject Test");
      final xObject = await barcode.createFormXObject(pdf, DeviceGray(0));

      // Draw XObject on canvas
      await canvas.addXObjectWithTransformationMatrix(
          xObject.getPdfObject(), 1, 0, 0, 1, 50, 600);

      await pdf.close();
      expect(file.existsSync(), isTrue);
    });
  });
}
