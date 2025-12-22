import 'package:test/test.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/layout/document.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'dart:io';

void main() {
  group('Document Layout Test', () {
    test('Layout simple document', () async {
      final file = File('test/layout/document_layout_test.pdf');
      final writer = PdfWriter.toFile(file.path);
      final pdfDoc = await PdfDocument.create(writer);
      final doc = Document(pdfDoc);

      final ttf = TrueTypeFont.fromFile("c:/windows/fonts/arial.ttf");

      // Need to register font or set it property
      // Document sets standard font usually, but let's be explicit
      final font = PdfTrueTypeFont(ttf);

      // Add a paragraph
      // Paragraph renderer not fully implemented?
      // BlockRenderer handles children. Paragraph extends BlockElement.
      // So ParagraphRenderer -> BlockRenderer logic.
      // Paragraph adds Text children.

      // Since ParagraphRenderer/Paragraph might be complex, let's just add Div with Text if Div exists, or Paragraph if I implemented it.
      // I have BlockRenderer.
      // I assume Paragraph uses BlockRenderer or ParagraphRenderer extends BlockRenderer.

      // Checking available elements: Text, Div?
      // I saw Div imported in BlockRenderer snippet in my thought.

      final text = Text("Hello Document Layout World!");
      text.setProperty(Property.FONT, font);
      text.setProperty(Property.FONT_SIZE, UnitValue.createPointValue(12));

      // If I add Text directly to Document?
      // Document.add takes IBlockElement. Text is ILeafElement / ILargeElement?
      // Text acts like inline usually.
      // Need a Paragraph wrapper.

      final p = Paragraph();
      p.add(text);

      // Add directly? Paragraph extends BlockElement?
      doc.add(p);

      doc.close();

      expect(await file.exists(), isTrue);
      // Can't easily check content without pdf reader, but existence confirms no crash.
    });
  });
}
