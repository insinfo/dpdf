import 'dart:typed_data';

import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/layout/document.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/text_alignment.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/render/page_renderer.dart';
import 'package:test/test.dart';

const _phrase = 'Hello Document Layout World!';

PdfTrueTypeFont _font() =>
    PdfTrueTypeFont(TrueTypeFont.fromFile(r'test/assets/ABeeZee-Regular.ttf'));

Paragraph _paragraph(String value) => Paragraph()
  ..add(Text(value))
  ..setProperty(Property.FONT, _font())
  ..setProperty(Property.FONT_SIZE, UnitValue.createPointValue(24));

/// Pixels that are neither transparent nor white, i.e. ink the renderer laid
/// down. A blank page has none of them.
int _inkedPixels(Uint32List pixels) {
  var inked = 0;
  for (final pixel in pixels) {
    if ((pixel >> 24) & 0xff == 0) continue;
    if (pixel & 0xffffff != 0xffffff) inked++;
  }
  return inked;
}

void main() {
  group('Document layout', () {
    test('a paragraph added to a document reaches the page', () async {
      final output = BytesBuilder(copy: false);
      final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
      final doc = Document(pdf);

      doc.add(_paragraph(_phrase));

      await doc.close();
      await pdf.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
      addTearDown(reopened.close);
      expect(reopened.pageTotal(), 1);

      final page = (await reopened.pageAt(1))!;
      expect(await PdfTextExtraction.fromPage(page), contains(_phrase));

      final rendered = await PdfPageRenderer.render(page);
      expect(rendered.report.glyphsSkipped, 0,
          reason: 'the embedded font should have drawn every glyph');
      expect(_inkedPixels(rendered.pixels), greaterThan(0),
          reason: 'the page renders blank, so nothing was drawn');
    });

    test('add is synchronous and defers every bit of the work', () async {
      final output = BytesBuilder(copy: false);
      final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
      final doc = Document(pdf);

      doc.add(_paragraph(_phrase));

      // add() touched nothing: no page exists yet, and the element is only
      // recorded.
      expect(pdf.pageTotal(), 0);
      expect(doc.pendingContentCount(), 1);

      await doc.close();

      expect(pdf.pageTotal(), 1);
      expect(doc.pendingContentCount(), 0);
      await pdf.close();
    });

    test('the queue keeps the order elements were added in', () async {
      final output = BytesBuilder(copy: false);
      final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
      final doc = Document(pdf);

      doc.add(_paragraph('primeiro'));
      doc.add(_paragraph('segundo'));
      doc.add(_paragraph('terceiro'));

      await doc.close();
      await pdf.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
      addTearDown(reopened.close);
      final text =
          await PdfTextExtraction.fromPage((await reopened.pageAt(1))!);
      expect(text.indexOf('primeiro'), lessThan(text.indexOf('segundo')));
      expect(text.indexOf('segundo'), lessThan(text.indexOf('terceiro')));
    });

    test('closing the PdfDocument with content still queued is refused',
        () async {
      final output = BytesBuilder(copy: false);
      final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
      final doc = Document(pdf);

      doc.add(_paragraph(_phrase));

      await expectLater(
          pdf.close(),
          throwsA(isA<PdfException>().having((e) => e.toString(), 'message',
              contains('still queued for layout'))));

      // The document is intact: closing the layout root first works.
      await doc.close();
      await pdf.close();
      expect(output.length, greaterThan(0));
    });

    test('showTextAligned queues as well and places its text', () async {
      final output = BytesBuilder(copy: false);
      final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
      final doc = Document(pdf);

      doc.showTextAligned(
          text: 'Centered Text',
          x: 200,
          y: 400,
          textAlign: TextAlignment.center);
      expect(pdf.pageTotal(), 0, reason: 'nothing may happen before close()');

      await doc.close();
      await pdf.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
      addTearDown(reopened.close);
      expect(await PdfTextExtraction.fromPage((await reopened.pageAt(1))!),
          contains('Centered Text'));
    });

    test('a closed document refuses further content', () async {
      final output = BytesBuilder(copy: false);
      final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
      final doc = Document(pdf);
      await doc.close();
      expect(() => doc.add(_paragraph(_phrase)), throwsStateError);
      await pdf.close();
    });
  });
}
