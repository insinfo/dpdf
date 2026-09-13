import 'dart:typed_data';

import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/annot/pdf_annotation.dart';
import 'package:dpdf/src/kernel/pdf/annot/pdf_print_annotations.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_date.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/prepress/pdf_printer_mark_form.dart';
import 'package:dpdf/src/kernel/pdf/prepress/pdf_trap_network.dart';
import 'package:test/test.dart';

PdfArray separationSpace(String colorant) => PdfArray.fromList([
      PdfName('Separation'),
      PdfName(colorant),
      PdfName('DeviceGray'),
      PdfDictionary.fromMap({
        PdfName.intern('FunctionType'): PdfNumber.fromInt(2),
        PdfName.intern('Domain'): PdfArray.fromDoubles([0, 1]),
        PdfName.intern('N'): PdfNumber.fromInt(1),
      }),
    ]);

void main() {
  group('Printer\'s mark form, ISO 32000-1 14.11.3', () {
    test('a colour bar form survives a write and reopen', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);

      final form = PdfPrinterMarkForm(Rectangle(0, 0, 120, 12))
        ..setMarkStyle('Colour bar, CMYK');
      await form.addColorant('Cyan', separationSpace('Cyan'));
      await form.addColorant('Magenta', separationSpace('Magenta'));
      form.pdfRepresentation().attachToDocument(document);

      final annotation =
          PdfPrinterMarkAnnotation.fromRect(Rectangle(20, 5, 120, 12))
            ..setMarkName(PdfName('ColorBar'))
            ..setFlags(PdfAnnotation.print | PdfAnnotation.readOnly);
      await annotation.setNormalAppearance(form.pdfRepresentation());
      await page.addAnnotation(annotation);
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final reloadedPage = (await reopened.pageAt(1))!;
      final annots =
          await reloadedPage.pdfRepresentation().arrayEntry(PdfName.annots);
      final loadedAnnotation = (await annots!.dictionaryEntry(0))!;

      expect(await validatePrinterMarkAnnotation(loadedAnnotation), isEmpty);
      expect(
          (await loadedAnnotation.nameEntry(PdfName.intern('MN')))!.getValue(),
          'ColorBar');

      final ap = (await loadedAnnotation.dictionaryEntry(PdfName.ap))!;
      final normal = (await ap.streamEntry(PdfName.n))!;
      final loadedForm = PdfPrinterMarkForm.fromStream(normal);
      expect(await loadedForm.getMarkStyle(), 'Colour bar, CMYK');
      expect(await loadedForm.colorantNames(), ['Cyan', 'Magenta']);
      expect(await loadedForm.validate(), isEmpty);
      expect(
          await PdfPrinterMarkForm.separationColorantName(
              (await loadedForm.getColorant('Cyan'))!),
          'Cyan');
    });

    test('a colorant key has to match the colour space colorant name',
        () async {
      final form = PdfPrinterMarkForm(Rectangle(0, 0, 10, 10));
      expect(() => form.addColorant('Cyan', separationSpace('Magenta')),
          throwsArgumentError);
      expect(
          () => form.addColorant(
              'Cyan',
              PdfArray.fromList([
                PdfName('DeviceN'),
                PdfName('Cyan'),
                PdfName('DeviceGray')
              ])),
          throwsArgumentError);
      expect(
          () => form.addColorant('', separationSpace('')), throwsArgumentError);
    });

    test('validate reports a mismatched /Colorants key written directly',
        () async {
      final form = PdfPrinterMarkForm(Rectangle(0, 0, 10, 10));
      final colorants = PdfDictionary();
      colorants.put(PdfName('Cyan'), separationSpace('Magenta'));
      colorants.put(PdfName('Spot'), PdfNumber.fromInt(1));
      form.pdfRepresentation().put(PdfPrinterMarkForm.colorants, colorants);

      final problems = await form.validate();
      expect(problems, contains(contains('/Colorants key /Cyan')));
      expect(problems, contains(contains('/Colorants entry /Spot')));
    });

    test('validate reports a form without /BBox or with a wrong /Subtype',
        () async {
      final stream = PdfStream();
      stream.put(PdfName.type, PdfName('XObject'));
      stream.put(PdfName.subtype, PdfName('Image'));
      final form = PdfPrinterMarkForm.fromStream(stream);
      final problems = await form.validate();
      expect(problems, contains(contains('/BBox')));
      expect(problems, contains(contains('/Subtype')));
    });

    test('the annotation shall carry /AP and the Print and ReadOnly flags only',
        () async {
      final annotation = PdfDictionary();
      annotation.put(PdfName.subtype, PdfName('PrinterMark'));
      var problems = await validatePrinterMarkAnnotation(annotation);
      expect(problems, contains(contains('/AP shall be present')));
      expect(problems, contains(contains('/F shall be present')));

      final ap = PdfDictionary();
      ap.put(PdfName.n, PdfStream());
      annotation.put(PdfName.ap, ap);
      annotation.put(PdfName.f, PdfNumber.fromInt(PdfAnnotation.print));
      problems = await validatePrinterMarkAnnotation(annotation);
      expect(problems,
          contains(contains('Print and ReadOnly flags of /F shall be set')));

      annotation.put(
          PdfName.f,
          PdfNumber.fromInt(PdfAnnotation.print |
              PdfAnnotation.readOnly |
              PdfAnnotation.hidden));
      problems = await validatePrinterMarkAnnotation(annotation);
      expect(problems, contains(contains('Only the Print and ReadOnly flags')));

      annotation.put(PdfName.f,
          PdfNumber.fromInt(PdfAnnotation.print | PdfAnnotation.readOnly));
      expect(await validatePrinterMarkAnnotation(annotation), isEmpty);
    });

    test('/AS is required when /AP /N holds more than one appearance',
        () async {
      final annotation = PdfDictionary();
      annotation.put(PdfName.subtype, PdfName('PrinterMark'));
      annotation.put(PdfName.f,
          PdfNumber.fromInt(PdfAnnotation.print | PdfAnnotation.readOnly));
      final normal = PdfDictionary();
      normal.put(PdfName('European'), PdfStream());
      normal.put(PdfName('Japanese'), PdfStream());
      final ap = PdfDictionary();
      ap.put(PdfName.n, normal);
      annotation.put(PdfName.ap, ap);

      expect(await validatePrinterMarkAnnotation(annotation),
          contains(contains('/AS shall be present')));

      annotation.put(PdfName.as, PdfName('European'));
      expect(await validatePrinterMarkAnnotation(annotation), isEmpty);
    });

    test('a wrong subtype and a non-name /MN are reported', () async {
      final annotation = PdfDictionary();
      annotation.put(PdfName.subtype, PdfName('Square'));
      annotation.put(PdfName.intern('MN'), PdfString('ColorBar'));
      final problems = await validatePrinterMarkAnnotation(annotation);
      expect(problems, contains(contains('/Subtype shall be /PrinterMark')));
      expect(problems, contains(contains('/MN shall be a name')));
    });
  });

  group('Trapping support, ISO 32000-1 14.11.6', () {
    test('a trap network annotation and appearance survive a reopen', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);

      final network = PdfTrapNetworkAppearance(Rectangle(0, 0, 595, 842))
        ..setProcessColorModel(PdfProcessColorModel.deviceCmyk)
        ..setSeparationColorNames(['PANTONE 35 CV'])
        ..setTrapStyles('Default press traps');
      network.pdfRepresentation().attachToDocument(document);

      final annotation =
          PdfTrapNetworkAnnotation.fromRect(Rectangle(0, 0, 595, 842))
            ..setLastModified(PdfDate(DateTime.utc(2024, 1, 1)))
            ..setFlags(PdfAnnotation.print | PdfAnnotation.readOnly);
      await addTrapNetwork(annotation.pdfRepresentation(), 'Press', network);
      await page.addAnnotation(annotation);
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final reloadedPage = (await reopened.pageAt(1))!.pdfRepresentation();
      expect(await validatePageTrapNetworks(reloadedPage), isEmpty);

      final annots = await reloadedPage.arrayEntry(PdfName.annots);
      final loaded = (await annots!.dictionaryEntry(0))!;
      expect(await validateTrapNetworkAnnotation(loaded), isEmpty);
      expect((await loaded.nameEntry(PdfName.as))!.getValue(), 'Press');

      final ap = (await loaded.dictionaryEntry(PdfName.ap))!;
      final normal = (await ap.dictionaryEntry(PdfName.n))!;
      final appearance = PdfTrapNetworkAppearance.fromStream(
          (await normal.streamEntry(PdfName('Press')))!);
      expect(await appearance.getProcessColorModel(),
          PdfProcessColorModel.deviceCmyk);
      expect(await appearance.getSeparationColorNames(), ['PANTONE 35 CV']);
      expect(await appearance.getTrapStyles(), 'Default press traps');
      expect(await appearance.effectiveColorants(),
          ['Cyan', 'Magenta', 'Yellow', 'Black', 'PANTONE 35 CV']);
      expect(await appearance.validate(), isEmpty);
    });

    test('an unknown process colour model is refused', () {
      final network = PdfTrapNetworkAppearance(Rectangle(0, 0, 10, 10));
      expect(
          () => network.setProcessColorModel('DeviceLab'), throwsArgumentError);
    });

    test('an absent /SeparationColorNames leaves the /PCM colorants', () async {
      final network = PdfTrapNetworkAppearance(Rectangle(0, 0, 10, 10))
        ..setProcessColorModel(PdfProcessColorModel.deviceRgbk);
      expect(await network.getSeparationColorNames(), isNull);
      expect(await network.effectiveColorants(),
          ['Red', 'Green', 'Blue', 'Black']);
      expect(await network.validate(), isEmpty);
    });

    test('validate reports a missing /PCM and a non-indirect /TrapRegions',
        () async {
      final network = PdfTrapNetworkAppearance(Rectangle(0, 0, 10, 10));
      network.pdfRepresentation().put(PdfTrapNetworkAppearance.trapRegions,
          PdfArray.fromList([PdfDictionary()]));
      final problems = await network.validate();
      expect(problems, contains(contains('/PCM is required')));
      expect(problems, contains(contains('/TrapRegions entry 0')));
    });

    test('/TrapRegions refuses a direct object', () {
      final network = PdfTrapNetworkAppearance(Rectangle(0, 0, 10, 10));
      expect(
          () => network.setTrapRegions([PdfDictionary()]), throwsArgumentError);
    });

    test('/LastModified and the /Version /AnnotStates pair are exclusive',
        () async {
      final annotation = PdfDictionary();
      annotation.put(PdfName.subtype, PdfName('TrapNet'));
      annotation.put(PdfName.f,
          PdfNumber.fromInt(PdfAnnotation.print | PdfAnnotation.readOnly));
      annotation.put(PdfName.as, PdfName('Press'));
      final ap = PdfDictionary();
      ap.put(PdfName.n, PdfStream());
      annotation.put(PdfName.ap, ap);

      expect(await validateTrapNetworkAnnotation(annotation),
          contains(contains('either /LastModified or both')));

      annotation.put(PdfName.intern('LastModified'),
          PdfString(PdfDate(DateTime.utc(2024, 5, 5)).getValue()));
      expect(await validateTrapNetworkAnnotation(annotation), isEmpty);

      annotation.put(PdfName.intern('Version'), PdfArray());
      annotation.put(PdfName.intern('AnnotStates'), PdfArray());
      expect(await validateTrapNetworkAnnotation(annotation),
          contains(contains('/LastModified shall be absent')));

      annotation.remove(PdfName.intern('LastModified'));
      expect(await validateTrapNetworkAnnotation(annotation), isEmpty);

      annotation.remove(PdfName.intern('AnnotStates'));
      final problems = await validateTrapNetworkAnnotation(annotation);
      expect(problems, contains(contains('shall be present together')));
    });

    test('the trap network annotation shall be the last element of /Annots',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);
      final trap = PdfTrapNetworkAnnotation.fromRect(Rectangle(0, 0, 10, 10))
        ..setFlags(PdfAnnotation.print | PdfAnnotation.readOnly);
      await page.addAnnotation(trap);
      final mark = PdfPrinterMarkAnnotation.fromRect(Rectangle(0, 0, 10, 10))
        ..setFlags(PdfAnnotation.print | PdfAnnotation.readOnly);
      await page.addAnnotation(mark);

      expect(await validatePageTrapNetworks(page.pdfRepresentation()),
          contains(contains('last element of /Annots')));
      await document.close();
    });

    test('a page carries at most one trap network annotation', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);
      for (var i = 0; i < 2; i++) {
        await page.addAnnotation(
            PdfTrapNetworkAnnotation.fromRect(Rectangle(0, 0, 10, 10)));
      }

      expect(await validatePageTrapNetworks(page.pdfRepresentation()),
          contains(contains('at most one trap network annotation')));
      await document.close();
    });

    test(
        '/AnnotStates lists one entry per annotation other than the trap '
        'network itself', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);
      await page.addAnnotation(
          PdfPrinterMarkAnnotation.fromRect(Rectangle(0, 0, 10, 10)));
      await page.addAnnotation(
          PdfPrinterMarkAnnotation.fromRect(Rectangle(0, 0, 10, 10)));
      final trap = PdfTrapNetworkAnnotation.fromRect(Rectangle(0, 0, 10, 10))
        ..setVersion(PdfArray())
        ..setAnnotationStates(PdfArray.fromList([PdfName('Off')]));
      await page.addAnnotation(trap);

      expect(await validatePageTrapNetworks(page.pdfRepresentation()),
          contains(contains('/AnnotStates shall list one entry per')));

      trap.setAnnotationStates(
          PdfArray.fromList([PdfName('Off'), PdfName('Off')]));
      expect(await validatePageTrapNetworks(page.pdfRepresentation()), isEmpty);
      await document.close();
    });

    test('a page modified after its trap network needs a regeneration',
        () async {
      final page = PdfDictionary();
      final annotation = PdfDictionary();
      final key = PdfName.intern('LastModified');

      expect(await trapNetworkNeedsRegeneration(page, annotation), isFalse);

      annotation.put(
          key, PdfString(PdfDate(DateTime.utc(2024, 1, 1)).getValue()));
      expect(await trapNetworkNeedsRegeneration(page, annotation), isFalse);

      page.put(key, PdfString(PdfDate(DateTime.utc(2023, 1, 1)).getValue()));
      expect(await trapNetworkNeedsRegeneration(page, annotation), isFalse);

      page.put(key, PdfString(PdfDate(DateTime.utc(2025, 1, 1)).getValue()));
      expect(await trapNetworkNeedsRegeneration(page, annotation), isTrue);
    });

    test('an unreadable date does not claim a regeneration is needed',
        () async {
      final page = PdfDictionary()
        ..put(PdfName.intern('LastModified'), PdfString('not a date'));
      final annotation = PdfDictionary()
        ..put(PdfName.intern('LastModified'),
            PdfString(PdfDate(DateTime.utc(2024, 1, 1)).getValue()));
      expect(await trapNetworkNeedsRegeneration(page, annotation), isFalse);
    });
  });
}
