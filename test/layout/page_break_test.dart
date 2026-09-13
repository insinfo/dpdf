import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';
import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/layout/document.dart';
import 'package:dpdf/src/layout/element/area_break.dart';
import 'package:dpdf/src/layout/element/div.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/properties/area_break_type.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/renderer/area_break_renderer.dart';

PdfTrueTypeFont _font() =>
    PdfTrueTypeFont(TrueTypeFont.fromFile(r'test/assets/ABeeZee-Regular.ttf'));

Paragraph _paragraph(String text) {
  final p = Paragraph();
  p.add(Text(text));
  p.setProperty(Property.FONT, _font());
  return p;
}

Div _block(double height) => Div()..setMinHeight(height);

void main() {
  test('an area break renderer reports the break it carries', () {
    final areaBreak = AreaBreak(AreaBreakType.NEXT_PAGE);
    final renderer = AreaBreakRenderer(areaBreak);
    final result = renderer
        .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 100, 100))));
    expect(result, isNotNull);
    expect(result!.getStatus(), LayoutResult.NOTHING);
    expect(result.getAreaBreak(), same(areaBreak));
    expect(result.getAreaBreak()!.getAreaBreakType(), AreaBreakType.NEXT_PAGE);
  });

  test('an area break starts a new page instead of looping', () async {
    final bytes = BytesBuilder();
    final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
    final doc = Document(pdf);

    await doc.add(_paragraph('primeira pagina'));
    await doc.add(AreaBreak(AreaBreakType.NEXT_PAGE));
    await doc.add(_paragraph('segunda pagina'));

    await doc.close();
    await pdf.close();

    final reopened =
        await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
    addTearDown(reopened.close);
    expect(reopened.pageTotal(), 2);
  });

  test('an area break can request a different page size', () async {
    final bytes = BytesBuilder();
    final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
    final doc = Document(pdf);

    await doc.add(_paragraph('a4'));
    await doc.add(AreaBreak.withPageSize(PageSize.A5));
    await doc.add(_paragraph('a5'));

    await doc.close();
    await pdf.close();

    final reopened =
        await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
    addTearDown(reopened.close);
    expect(reopened.pageTotal(), 2);
    final second = await reopened.pageAt(2);
    final bounds = await second!.mediaBounds();
    expect(bounds.getWidth().round(), PageSize.A5.getWidth().round());
  });

  test('content taller than one page is split over several pages', () async {
    final bytes = BytesBuilder();
    final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
    final doc = Document(pdf);

    final tall = Div();
    for (int i = 0; i < 12; i++) {
      tall.add(_block(100));
    }
    await doc.add(tall);

    await doc.close();
    await pdf.close();

    final reopened =
        await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
    addTearDown(reopened.close);
    expect(reopened.pageTotal(), greaterThan(1));
  });

  test('keep-together refuses a partial placement', () {
    final root = Div()
      ..setKeepTogether(true)
      ..add(_block(100))
      ..add(_block(100));
    final renderer = root.createRendererSubTree()!;
    final result = renderer
        .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 150))));
    expect(result, isNotNull);
    expect(result!.getStatus(), LayoutResult.NOTHING);
    expect(result.getOverflowRenderer(), isNotNull);
  });

  test('without keep-together the block is split', () {
    final root = Div()
      ..add(_block(100))
      ..add(_block(100));
    final renderer = root.createRendererSubTree()!;
    final result = renderer
        .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 150))));
    expect(result, isNotNull);
    expect(result!.getStatus(), LayoutResult.PARTIAL);
    expect(result.getSplitRenderer()!.getChildRenderers().length, 1);
    expect(result.getOverflowRenderer()!.getChildRenderers().length, 1);
  });

  test('keep-with-next moves a block together with its successor', () {
    final root = Div()
      ..add(_block(50))
      ..add(_block(50)..setProperty(Property.KEEP_WITH_NEXT, true))
      ..add(_block(100));
    final renderer = root.createRendererSubTree()!;
    final result = renderer
        .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 160))));
    expect(result, isNotNull);
    expect(result!.getStatus(), LayoutResult.PARTIAL);
    // Only the first block stays: the tagged one travels with the next block.
    expect(result.getSplitRenderer()!.getChildRenderers().length, 1);
    expect(result.getOverflowRenderer()!.getChildRenderers().length, 2);
  });

  test('a fixed positioned block is laid out in its own rectangle', () {
    final fixed = Div()
      ..setMinHeight(40)
      ..setFixedPosition(1, 30, 60, 120);
    final renderer = fixed.createRendererSubTree()!;
    final result = renderer
        .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 400, 400))));
    expect(result, isNotNull);
    final box = result!.getOccupiedArea()!.getBBox();
    expect(box.getX(), 30);
    expect(box.getWidth(), 120);
    expect(box.getHeight(), 40);
  });

  test('a fixed positioned child does not consume space in its parent', () {
    final root = Div()
      ..add(_block(50))
      ..add(Div()
        ..setMinHeight(40)
        ..setFixedPosition(1, 10, 10, 80));
    final renderer = root.createRendererSubTree()!;
    final result = renderer
        .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 400))));
    expect(result!.getOccupiedArea()!.getBBox().getHeight(), 50);
  });
}
