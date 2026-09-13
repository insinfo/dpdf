import 'dart:typed_data';

import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_page.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/prepress/pdf_separation_info.dart';
import 'package:test/test.dart';

/// A `[/Separation name /DeviceGray tint]` colour space array of 8.6.6.4; the
/// tint transform is a type 2 exponential function of 7.10.3.
PdfArray separationSpace(String colorant) => PdfArray.fromList([
      PdfName('Separation'),
      PdfName(colorant),
      PdfName('DeviceGray'),
      PdfDictionary.fromMap({
        PdfName.intern('FunctionType'): PdfNumber.fromInt(2),
        PdfName.intern('Domain'): PdfArray.fromDoubles([0, 1]),
        PdfName.intern('C0'): PdfArray.fromDoubles([1]),
        PdfName.intern('C1'): PdfArray.fromDoubles([0]),
        PdfName.intern('N'): PdfNumber.fromInt(1),
      }),
    ]);

/// A `[/DeviceN names /DeviceGray tint]` colour space array of 8.6.6.5.
PdfArray deviceNSpace(List<String> colorants) => PdfArray.fromList([
      PdfName('DeviceN'),
      PdfArray.fromStrings(colorants, asNames: true),
      PdfName('DeviceGray'),
      PdfDictionary.fromMap({
        PdfName.intern('FunctionType'): PdfNumber.fromInt(2),
        PdfName.intern('Domain'): PdfArray.fromDoubles([0, 1]),
        PdfName.intern('N'): PdfNumber.fromInt(1),
      }),
    ]);

void main() {
  group('Separation dictionaries, ISO 32000-1 14.11.4', () {
    test('a preseparated CMYK page survives a write and reopen', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final colorants = ['Cyan', 'Magenta', 'Yellow', 'Black'];
      final pages = <PdfPage>[];
      for (var i = 0; i < colorants.length; i++) {
        pages.add(await document.appendBlankPage(PageSize.A4));
      }
      PdfSeparationInfo.buildGroup([
        for (var i = 0; i < colorants.length; i++)
          MapEntry(pages[i], colorants[i])
      ]);
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);

      final loadedPages = <PdfDictionary>[];
      for (var i = 1; i <= colorants.length; i++) {
        loadedPages.add((await reopened.pageAt(i))!.pdfRepresentation());
      }

      for (var i = 0; i < colorants.length; i++) {
        final info = await PdfSeparationInfo.ofPage(loadedPages[i]);
        expect(info, isNotNull, reason: colorants[i]);
        expect(await info!.getDeviceColorant(), colorants[i]);
        final listed = await info.getPages();
        expect(listed.length, colorants.length);
        expect(identical(listed[i], loadedPages[i]), isTrue);
        expect(await info.validate(owner: loadedPages[i]), isEmpty);
      }

      expect(await PdfSeparationInfo.validateGroup(loadedPages), isEmpty);
    });

    test('a spot colorant may be written as a string', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);
      PdfSeparationInfo.buildGroup([MapEntry(page, 'PANTONE 35 CV')],
          colorantsAsNames: false);
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final loaded = (await reopened.pageAt(1))!.pdfRepresentation();
      final info = (await PdfSeparationInfo.ofPage(loaded))!;
      expect(await info.getDeviceColorant(), 'PANTONE 35 CV');
      expect(await info.validate(owner: loaded), isEmpty);
    });

    test('the colour space colorant name has to agree with /DeviceColorant',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);
      final info =
          PdfSeparationInfo.buildGroup([MapEntry(page, 'Cyan')]).single;
      info.setColorSpace(separationSpace('Magenta'));
      expect(await info.colorSpaceColorants(), ['Magenta']);
      expect(await info.validate(owner: page.pdfRepresentation()),
          contains(allOf(contains('/DeviceColorant'), contains('Cyan'))));

      info.setColorSpace(separationSpace('Cyan'));
      expect(await info.validate(owner: page.pdfRepresentation()), isEmpty);
      await document.close();
    });

    test('a DeviceN colour space may list the colorant among several',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);
      final info = PdfSeparationInfo.buildGroup([MapEntry(page, 'Yellow')])
          .single
        ..setColorSpace(deviceNSpace(['Cyan', 'Magenta', 'Yellow']));
      expect(await info.colorSpaceColorants(), ['Cyan', 'Magenta', 'Yellow']);
      expect(await info.validate(owner: page.pdfRepresentation()), isEmpty);

      info.setColorSpace(deviceNSpace(['Cyan', 'Magenta']));
      expect(await info.validate(owner: page.pdfRepresentation()), isNotEmpty);
      await document.close();
    });

    test('the colour space array survives a reopen', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);
      PdfSeparationInfo.buildGroup([MapEntry(page, 'Cyan')])
          .single
          .setColorSpace(separationSpace('Cyan'));
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final loaded = (await reopened.pageAt(1))!.pdfRepresentation();
      final info = (await PdfSeparationInfo.ofPage(loaded))!;
      expect(await info.colorSpaceColorants(), ['Cyan']);
      expect(await info.validate(owner: loaded), isEmpty);
    });

    test('validate reports the missing required entries', () async {
      final info = PdfSeparationInfo.create();
      final problems = await info.validate();
      expect(problems, contains(contains('/Pages is required')));
      expect(problems, contains(contains('/DeviceColorant is required')));
    });

    test('validate reports a /Pages array of direct dictionaries', () async {
      final info = PdfSeparationInfo.create();
      info.pdfRepresentation().put(PdfSeparationInfo.pages,
          PdfArray.fromList([PdfDictionary(), PdfDictionary()]));
      info.setDeviceColorantName('Cyan');
      final problems = await info.validate();
      expect(problems.where((p) => p.contains('indirect reference')).length, 2);
    });

    test('validate reports a page missing from its own /Pages array', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final first = await document.appendBlankPage(PageSize.A4);
      final second = await document.appendBlankPage(PageSize.A4);
      final info = PdfSeparationInfo.create()
        ..setPages([second.pdfRepresentation()])
        ..setDeviceColorantName('Cyan')
        ..attachToPage(first.pdfRepresentation());

      expect(await info.validate(owner: first.pdfRepresentation()),
          contains(allOf(contains('/Pages'), contains('associated with'))));
      await document.close();
    });

    test('validateGroup reports diverging /Pages arrays', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final first = await document.appendBlankPage(PageSize.A4);
      final second = await document.appendBlankPage(PageSize.A4);
      final both = [first.pdfRepresentation(), second.pdfRepresentation()];

      PdfSeparationInfo.create()
        ..setPages(both)
        ..setDeviceColorantName('Cyan')
        ..attachToPage(first.pdfRepresentation());
      PdfSeparationInfo.create()
        ..setPages([second.pdfRepresentation()])
        ..setDeviceColorantName('Magenta')
        ..attachToPage(second.pdfRepresentation());

      expect(await PdfSeparationInfo.validateGroup(both),
          contains(contains('differs from the first one')));
      await document.close();
    });

    test('validateGroup reports a page without /SeparationInfo', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final first = await document.appendBlankPage(PageSize.A4);
      final second = await document.appendBlankPage(PageSize.A4);
      PdfSeparationInfo.create()
        ..setPages([first.pdfRepresentation(), second.pdfRepresentation()])
        ..setDeviceColorantName('Cyan')
        ..attachToPage(first.pdfRepresentation());

      expect(
          await PdfSeparationInfo.validateGroup(
              [first.pdfRepresentation(), second.pdfRepresentation()]),
          contains(contains('has no /SeparationInfo')));
      await document.close();
    });

    test('validateGroup reports the same colorant used twice', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final first = await document.appendBlankPage(PageSize.A4);
      final second = await document.appendBlankPage(PageSize.A4);
      final both = [first.pdfRepresentation(), second.pdfRepresentation()];
      PdfSeparationInfo.buildGroup(
          [MapEntry(first, 'Cyan'), MapEntry(second, 'Cyan')]);

      expect(await PdfSeparationInfo.validateGroup(both),
          contains(contains('more than one separation')));
      await document.close();
    });

    test('a page without an indirect reference cannot go into /Pages', () {
      final info = PdfSeparationInfo.create();
      expect(() => info.setPages([PdfDictionary()]), throwsArgumentError);
      expect(() => info.setPages([]), throwsArgumentError);
    });

    test('an empty colorant name is refused', () {
      final info = PdfSeparationInfo.create();
      expect(() => info.setDeviceColorantName(''), throwsArgumentError);
      expect(() => info.setDeviceColorantString(''), throwsArgumentError);
    });

    test('buildGroup refuses an empty group', () {
      expect(() => PdfSeparationInfo.buildGroup([]), throwsArgumentError);
    });
  });
}
