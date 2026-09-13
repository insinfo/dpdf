import 'dart:typed_data';

import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_output_intent.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:test/test.dart';

/// A stand-in for the ICC profile stream of 8.6.5.5; only `/N` and the body
/// matter to the entries under test.
PdfStream iccProfile(int components) {
  final stream = PdfStream.withBytes(
      Uint8List.fromList(List<int>.generate(64, (i) => i)), 0);
  stream.put(PdfName.intern('N'), PdfNumber.fromInt(components));
  return stream;
}

void main() {
  group('Output intents, ISO 32000-1 14.11.5', () {
    test('a PDF/X intent with a registry condition survives a reopen',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await document.appendBlankPage(PageSize.A4);
      final intent = PdfOutputIntent.pdfX('CGATS TR 001',
          outputCondition: 'CGATS TR 001 (SWOP)',
          registryName: 'http://www.color.org',
          destOutputProfile: iccProfile(4));
      expect(await intent.validate(), isEmpty);
      document.registerOutputProfile(intent);
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final intents = await reopened.rootCatalog().getOutputIntents();
      expect(intents, isNotNull);
      expect(intents!.size(), 1);

      final loaded = PdfOutputIntent((await intents.dictionaryEntry(0))!);
      expect(
          (await loaded.pdfRepresentation().nameEntry(PdfName.type))!
              .getValue(),
          'OutputIntent');
      expect((await loaded.getSubtype())!.getValue(), 'GTS_PDFX');
      expect(await loaded.getOutputConditionIdentifier(), 'CGATS TR 001');
      expect(await loaded.getOutputCondition(), 'CGATS TR 001 (SWOP)');
      expect(await loaded.getRegistryName(), 'http://www.color.org');
      expect(await loaded.getDestOutputProfile(), isNotNull);
      expect(await loaded.validate(), isEmpty);
    });

    test('a custom condition intent carries /Info and /DestOutputProfile',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await document.appendBlankPage(PageSize.A4);
      final intent = PdfOutputIntent.pdfX('Custom',
          outputCondition: 'Coated',
          info: 'Coated 150lpi',
          destOutputProfile: iccProfile(4));
      document.registerOutputProfile(intent);
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final intents = await reopened.rootCatalog().getOutputIntents();
      final loaded = PdfOutputIntent((await intents!.dictionaryEntry(0))!);

      expect(await loaded.namesStandardCondition(), isFalse);
      expect(await loaded.getInfo(), 'Coated 150lpi');
      expect(await loaded.validate(), isEmpty);
    });

    test('a custom condition without /Info or /DestOutputProfile is reported',
        () async {
      final intent = PdfOutputIntent.pdfX('Custom');
      final problems = await intent.validate();
      expect(problems, contains(contains('/Info is required')));
      expect(problems, contains(contains('/DestOutputProfile is required')));
    });

    test('a standard condition needs neither /Info nor /DestOutputProfile',
        () async {
      final intent = PdfOutputIntent.pdfA1('sRGB IEC61966-2.1',
          registryName: 'http://www.color.org');
      expect(await intent.namesStandardCondition(), isTrue);
      expect(await intent.validate(), isEmpty);
    });

    test('the three subtypes of 14.11.5 are written as named', () async {
      expect((await PdfOutputIntent.pdfX('c').getSubtype())!.getValue(),
          'GTS_PDFX');
      expect((await PdfOutputIntent.pdfA1('c').getSubtype())!.getValue(),
          'GTS_PDFA1');
      expect((await PdfOutputIntent.pdfE1('c').getSubtype())!.getValue(),
          'ISO_PDFE1');
      expect(PdfOutputIntent.standardSubtypes.map((n) => n.getValue()),
          ['GTS_PDFX', 'GTS_PDFA1', 'ISO_PDFE1']);
    });

    test('the legacy positional factory still defaults to /GTS_PDFA1',
        () async {
      final intent = PdfOutputIntent.create('sRGB IEC61966-2.1',
          'sRGB IEC61966-2.1', 'http://www.color.org', 'sRGB', null);
      expect((await intent.getSubtype())!.getValue(), 'GTS_PDFA1');
      expect(await intent.getInfo(), 'sRGB');
      expect(await intent.validate(), isEmpty);
    });

    test('an extension subtype is accepted', () async {
      final intent = PdfOutputIntent.create(
          'House condition', null, null, 'House', iccProfile(4),
          subtype: PdfName('ACME_HOUSE1'));
      expect((await intent.getSubtype())!.getValue(), 'ACME_HOUSE1');
      expect(await intent.validate(), isEmpty);
    });

    test('validate reports the missing required entries', () async {
      final intent = PdfOutputIntent(PdfDictionary());
      final problems = await intent.validate();
      expect(problems, contains(contains('/S is required')));
      expect(problems,
          contains(contains('/OutputConditionIdentifier is required')));
    });

    test('validate reports entries of the wrong type', () async {
      final dictionary = PdfDictionary();
      dictionary.put(PdfName.type, PdfName('OutputIntentt'));
      dictionary.put(PdfName.s, PdfName('GTS_PDFX'));
      dictionary.put(
          PdfName.outputConditionIdentifier, PdfString('CGATS TR 001'));
      dictionary.put(PdfName.outputCondition, PdfNumber.fromInt(3));
      dictionary.put(PdfName.destOutputProfile, PdfDictionary());
      final problems = await PdfOutputIntent(dictionary).validate();

      expect(problems, contains(contains('/Type shall be /OutputIntent')));
      expect(problems, contains(contains('/OutputCondition shall be a text')));
      expect(
          problems, contains(contains('/DestOutputProfile shall be an ICC')));
    });

    test('every Table 365 entry can be set on an existing dictionary',
        () async {
      final intent = PdfOutputIntent(PdfDictionary())
        ..setSubtype(PdfOutputIntent.isoPdfE1)
        ..setOutputConditionIdentifier('Custom')
        ..setOutputCondition('Engineering plot')
        ..setRegistryName('http://www.color.org')
        ..setInfo('Wide format plotter')
        ..setDestOutputProfile(iccProfile(3));

      expect((await intent.getSubtype())!.getValue(), 'ISO_PDFE1');
      expect(await intent.getOutputConditionIdentifier(), 'Custom');
      expect(await intent.getOutputCondition(), 'Engineering plot');
      expect(await intent.getRegistryName(), 'http://www.color.org');
      expect(await intent.getInfo(), 'Wide format plotter');
      expect(await intent.getDestOutputProfile(), isNotNull);
      expect(await intent.validate(), isEmpty);
    });
  });
}
