import 'dart:typed_data';

import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/prepress/pdf_box_color_info.dart';
import 'package:dpdf/src/kernel/pdf/prepress/pdf_page_boundaries.dart';
import 'package:test/test.dart';

/// Builds a one page document, lets [build] write the prepress entries and
/// returns the boundaries of the first page of the reopened file.
Future<PdfPageBoundaries> roundtrip(
    Future<void> Function(PdfPageBoundaries boundaries) build) async {
  final bytes = BytesBuilder();
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
  final page = await document.appendBlankPage(PageSize.A4);
  await build(PdfPageBoundaries.ofPage(page));
  await document.close();

  final reopened = await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
  addTearDown(reopened.close);
  final reloaded = (await reopened.pageAt(1))!;
  return PdfPageBoundaries.ofPage(reloaded);
}

void main() {
  group('Page boundaries, ISO 32000-1 14.11.2', () {
    test('all five boxes survive a write and reopen', () async {
      final boundaries = await roundtrip((boundaries) async {
        boundaries.setBox(PdfPageBox.media, Rectangle(0, 0, 640, 880));
        boundaries.setBox(PdfPageBox.crop, Rectangle(5, 5, 630, 870));
        boundaries.setBox(PdfPageBox.bleed, Rectangle(10, 10, 620, 860));
        boundaries.setBox(PdfPageBox.trim, Rectangle(20, 20, 600, 840));
        boundaries.setBox(PdfPageBox.art, Rectangle(30, 30, 580, 820));
      });

      expect(
          (await boundaries.declaredBox(PdfPageBox.media))!
              .equalsWithEpsilon(Rectangle(0, 0, 640, 880)),
          isTrue);
      expect(
          (await boundaries.declaredBox(PdfPageBox.bleed))!
              .equalsWithEpsilon(Rectangle(10, 10, 620, 860)),
          isTrue);
      expect(
          (await boundaries.declaredBox(PdfPageBox.trim))!
              .equalsWithEpsilon(Rectangle(20, 20, 600, 840)),
          isTrue);
      expect(
          (await boundaries.declaredBox(PdfPageBox.art))!
              .equalsWithEpsilon(Rectangle(30, 30, 580, 820)),
          isTrue);
      expect(await boundaries.validate(requireFigure86Nesting: true), isEmpty);
    });

    test(
        'crop box defaults to the media box and the three PDF 1.3 boxes '
        'default to the crop box', () async {
      final boundaries = await roundtrip((boundaries) async {
        boundaries.setBox(PdfPageBox.media, Rectangle(0, 0, 500, 700));
        boundaries.setBox(PdfPageBox.crop, Rectangle(10, 10, 480, 680));
      });

      expect(boundaries.hasOwnBox(PdfPageBox.bleed), isFalse);
      for (final box in [PdfPageBox.bleed, PdfPageBox.trim, PdfPageBox.art]) {
        expect(await boundaries.declaredBox(box), isNull, reason: '$box');
        expect(
            (await boundaries.resolvedBox(box))!
                .equalsWithEpsilon(Rectangle(10, 10, 480, 680)),
            isTrue,
            reason: '$box');
      }
    });

    test('a page without a crop box takes the media box for every default',
        () async {
      final boundaries = await roundtrip((boundaries) async {
        boundaries.setBox(PdfPageBox.media, Rectangle(0, 0, 200, 400));
      });

      for (final box in PdfPageBox.values) {
        expect(
            (await boundaries.resolvedBox(box))!
                .equalsWithEpsilon(Rectangle(0, 0, 200, 400)),
            isTrue,
            reason: '$box');
      }
    });

    test('media and crop boxes are inherited through /Parent', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);
      final pageDictionary = page.pdfRepresentation();
      pageDictionary.remove(PdfPageBoundaries.mediaBox);
      pageDictionary.remove(PdfPageBoundaries.cropBox);
      final parent = await pageDictionary.dictionaryEntry(PdfName.parent);
      expect(parent, isNotNull);
      parent!.put(
          PdfPageBoundaries.mediaBox, Rectangle(0, 0, 612, 792).toPdfArray());
      parent.put(
          PdfPageBoundaries.cropBox, Rectangle(6, 6, 600, 780).toPdfArray());
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final boundaries = PdfPageBoundaries.ofPage((await reopened.pageAt(1))!);

      expect(boundaries.hasOwnBox(PdfPageBox.media), isFalse);
      expect(
          (await boundaries.declaredBox(PdfPageBox.media))!
              .equalsWithEpsilon(Rectangle(0, 0, 612, 792)),
          isTrue);
      expect(
          (await boundaries.declaredBox(PdfPageBox.crop))!
              .equalsWithEpsilon(Rectangle(6, 6, 600, 780)),
          isTrue);
      expect(await boundaries.validate(), isEmpty);
    });

    test('the bleed box is not inherited through /Parent', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);
      final parent =
          await page.pdfRepresentation().dictionaryEntry(PdfName.parent);
      parent!.put(
          PdfPageBoundaries.bleedBox, Rectangle(3, 3, 100, 100).toPdfArray());
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final boundaries = PdfPageBoundaries.ofPage((await reopened.pageAt(1))!);

      expect(await boundaries.declaredBox(PdfPageBox.bleed), isNull);
    });

    test('a box larger than the media box is reduced to the intersection',
        () async {
      final boundaries = await roundtrip((boundaries) async {
        boundaries.setBox(PdfPageBox.media, Rectangle(0, 0, 300, 300));
        boundaries.setBox(PdfPageBox.bleed, Rectangle(-50, -50, 500, 500));
      });

      expect(
          (await boundaries.declaredBox(PdfPageBox.bleed))!
              .equalsWithEpsilon(Rectangle(-50, -50, 500, 500)),
          isTrue);
      expect(
          (await boundaries.effectiveBox(PdfPageBox.bleed))!
              .equalsWithEpsilon(Rectangle(0, 0, 300, 300)),
          isTrue);
      expect(await boundaries.validate(),
          contains(allOf(contains('/BleedBox'), contains('14.11.2.1'))));
    });

    test('a box disjoint from the media box gives an empty intersection',
        () async {
      final boundaries = await roundtrip((boundaries) async {
        boundaries.setBox(PdfPageBox.media, Rectangle(0, 0, 100, 100));
        boundaries.setBox(PdfPageBox.trim, Rectangle(500, 500, 50, 50));
      });

      final effective = await boundaries.effectiveBox(PdfPageBox.trim);
      expect(effective!.getWidth(), 0);
      expect(effective.getHeight(), 0);
    });

    test(
        'validate reports a trim box outside the bleed box only when the '
        'Figure 86 nesting is required', () async {
      final boundaries = await roundtrip((boundaries) async {
        boundaries.setBox(PdfPageBox.media, Rectangle(0, 0, 400, 400));
        boundaries.setBox(PdfPageBox.bleed, Rectangle(50, 50, 200, 200));
        boundaries.setBox(PdfPageBox.trim, Rectangle(10, 10, 380, 380));
      });

      expect(await boundaries.validate(), isEmpty);
      final strict = await boundaries.validate(requireFigure86Nesting: true);
      expect(
          strict, contains(allOf(contains('/TrimBox'), contains('/BleedBox'))));
    });

    test('validate reports an art box outside the trim box under Figure 86',
        () async {
      final boundaries = await roundtrip((boundaries) async {
        boundaries.setBox(PdfPageBox.media, Rectangle(0, 0, 400, 400));
        boundaries.setBox(PdfPageBox.bleed, Rectangle(10, 10, 380, 380));
        boundaries.setBox(PdfPageBox.trim, Rectangle(20, 20, 360, 360));
        boundaries.setBox(PdfPageBox.art, Rectangle(15, 15, 370, 370));
      });

      expect(await boundaries.validate(requireFigure86Nesting: true),
          contains(allOf(contains('/ArtBox'), contains('/TrimBox'))));
    });

    test('validate reports a missing media box', () async {
      final page = PdfDictionary();
      final boundaries = PdfPageBoundaries(page);
      expect(await boundaries.validate(),
          contains(allOf(contains('/MediaBox'), contains('required'))));
    });

    test('validate reports a malformed boundary array', () async {
      final page = PdfDictionary();
      page.put(
          PdfPageBoundaries.mediaBox, Rectangle(0, 0, 100, 100).toPdfArray());
      page.put(PdfPageBoundaries.trimBox,
          PdfArray.fromList([PdfNumber(0), PdfNumber(0), PdfNumber(10)]));
      final boundaries = PdfPageBoundaries(page);
      expect(await boundaries.validate(),
          contains(allOf(contains('/TrimBox'), contains('four'))));
    });

    test('validate reports a boundary array holding a non-number', () async {
      final page = PdfDictionary();
      page.put(
          PdfPageBoundaries.mediaBox, Rectangle(0, 0, 100, 100).toPdfArray());
      page.put(
          PdfPageBoundaries.artBox,
          PdfArray.fromList([
            PdfNumber(0),
            PdfNumber(0),
            PdfName('Ten'),
            PdfNumber(10),
          ]));
      final boundaries = PdfPageBoundaries(page);
      expect(await boundaries.validate(),
          contains(allOf(contains('/ArtBox'), contains('numbers only'))));
    });

    test('a negative extent is refused when a boundary is written', () async {
      final boundaries = PdfPageBoundaries(PdfDictionary());
      expect(() => boundaries.setBox(PdfPageBox.trim, Rectangle(0, 0, -1, 10)),
          throwsArgumentError);
      expect(() => boundaries.setBox(PdfPageBox.trim, Rectangle(0, 0, 10, -1)),
          throwsArgumentError);
    });

    test('the media box cannot be removed', () async {
      final boundaries = PdfPageBoundaries(PdfDictionary());
      expect(() => boundaries.removeBox(PdfPageBox.media), throwsArgumentError);
    });

    test('removing a box restores its default', () async {
      final page = PdfDictionary();
      final boundaries = PdfPageBoundaries(page);
      boundaries.setBox(PdfPageBox.media, Rectangle(0, 0, 100, 200));
      boundaries.setBox(PdfPageBox.trim, Rectangle(5, 5, 50, 50));
      expect(boundaries.hasOwnBox(PdfPageBox.trim), isTrue);
      boundaries.removeBox(PdfPageBox.trim);
      expect(boundaries.hasOwnBox(PdfPageBox.trim), isFalse);
      expect(
          (await boundaries.resolvedBox(PdfPageBox.trim))!
              .equalsWithEpsilon(Rectangle(0, 0, 100, 200)),
          isTrue);
    });

    test('copyFrom transfers only the boxes actually written', () async {
      final source = PdfPageBoundaries(PdfDictionary());
      source.setBox(PdfPageBox.media, Rectangle(0, 0, 100, 100));
      source.setBox(PdfPageBox.trim, Rectangle(10, 10, 80, 80));

      final target = PdfPageBoundaries(PdfDictionary());
      await target.copyFrom(source);

      expect(target.hasOwnBox(PdfPageBox.media), isTrue);
      expect(target.hasOwnBox(PdfPageBox.trim), isTrue);
      expect(target.hasOwnBox(PdfPageBox.art), isFalse);
    });

    test('only the media and crop boxes are inheritable', () {
      expect(PdfPageBoundaries.isInheritable(PdfPageBox.media), isTrue);
      expect(PdfPageBoundaries.isInheritable(PdfPageBox.crop), isTrue);
      expect(PdfPageBoundaries.isInheritable(PdfPageBox.bleed), isFalse);
      expect(PdfPageBoundaries.isInheritable(PdfPageBox.trim), isFalse);
      expect(PdfPageBoundaries.isInheritable(PdfPageBox.art), isFalse);
    });
  });

  group('Box colour information, ISO 32000-1 14.11.2.2', () {
    test('a full box colour information dictionary survives a reopen',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);
      final info = PdfBoxColorInfo.create();
      info.setStyleFor(
          PdfPageBox.crop,
          PdfBoxStyle.create()
            ..setColour([1.0, 0.0, 0.0])
            ..setWidth(2.5)
            ..setStyle(PdfBoxGuidelineStyle.dashed)
            ..setDashArray([4.0, 2.0]));
      info.setStyleFor(PdfPageBox.trim, PdfBoxStyle.create());
      info.attachToPage(page.pdfRepresentation());
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final reloaded = (await reopened.pageAt(1))!;
      final loaded = await PdfBoxColorInfo.ofPage(reloaded.pdfRepresentation());
      expect(loaded, isNotNull);

      final crop = (await loaded!.getStyleFor(PdfPageBox.crop))!;
      expect(await crop.getColour(), [1.0, 0.0, 0.0]);
      expect(await crop.getWidth(), 2.5);
      expect(await crop.getStyle(), PdfBoxGuidelineStyle.dashed);
      expect(await crop.getDashArray(), [4.0, 2.0]);

      final trim = (await loaded.getStyleFor(PdfPageBox.trim))!;
      expect(await trim.getColour(), PdfBoxStyle.defaultColour);
      expect(await trim.getWidth(), PdfBoxStyle.defaultWidth);
      expect(await trim.getStyle(), PdfBoxGuidelineStyle.solid);
      expect(await trim.getDashArray(), PdfBoxStyle.defaultDashArray);

      expect(await loaded.getStyleFor(PdfPageBox.art), isNull);
    });

    test('the dictionary has no media box entry', () {
      final info = PdfBoxColorInfo.create();
      expect(() => info.setStyleFor(PdfPageBox.media, PdfBoxStyle.create()),
          throwsArgumentError);
      expect(
          PdfBoxColorInfo.describableBoxes, isNot(contains(PdfPageBox.media)));
    });

    test('an out of range colour component is refused', () {
      final style = PdfBoxStyle.create();
      expect(() => style.setColour([0.0, 1.5, 0.0]), throwsArgumentError);
      expect(() => style.setColour([0.0, -0.1, 0.0]), throwsArgumentError);
      expect(() => style.setColour([0.0, 0.0]), throwsArgumentError);
    });

    test('a negative guideline width and an empty dash array are refused', () {
      final style = PdfBoxStyle.create();
      expect(() => style.setWidth(-1), throwsArgumentError);
      expect(() => style.setDashArray([]), throwsArgumentError);
      expect(() => style.setDashArray([2.0, -1.0]), throwsArgumentError);
    });

    test('an unrecognised /S is reported as unknown rather than rejected',
        () async {
      final style = PdfBoxStyle.create()..setStyleName(PdfName('Wavy'));
      expect(await style.getStyle(), PdfBoxGuidelineStyle.unknown);
      expect((await style.getStyleName())!.getValue(), 'Wavy');
      expect(() => style.setStyle(PdfBoxGuidelineStyle.unknown),
          throwsArgumentError);
    });

    test('removing a style falls back to the reader defaults', () async {
      final info = PdfBoxColorInfo.create();
      info.setStyleFor(PdfPageBox.bleed, PdfBoxStyle.create()..setWidth(3));
      expect(await info.getStyleFor(PdfPageBox.bleed), isNotNull);
      info.removeStyleFor(PdfPageBox.bleed);
      expect(await info.getStyleFor(PdfPageBox.bleed), isNull);
    });
  });
}
