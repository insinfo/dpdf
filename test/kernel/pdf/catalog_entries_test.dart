import 'dart:typed_data';

import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_catalog.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_version.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/viewer/pdf_legal_attestation.dart';
import 'package:dpdf/src/kernel/pdf/viewer/pdf_page_layout.dart';
import 'package:test/test.dart';

/// Builds a one page document, lets [build] fill in catalog entries, closes it
/// and reopens the bytes, returning the reloaded catalog.
Future<PdfCatalog> roundtrip(
    Future<void> Function(PdfDocument, PdfCatalog) build) async {
  final bytes = BytesBuilder();
  final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
  await doc.appendBlankPage();
  await build(doc, doc.rootCatalog());
  await doc.close();

  final reopened = await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
  addTearDown(reopened.close);
  return reopened.rootCatalog();
}

void main() {
  group('document catalog (ISO 32000-1:2008, 7.7.2, Table 28)', () {
    test('PageLayout and PageMode survive a roundtrip', () async {
      final catalog = await roundtrip((doc, catalog) async {
        catalog
            .setPageLayoutMode(PdfPageLayout.twoPageRight)
            .setPageModeValue(PdfPageMode.useAttachments);
      });

      expect(await catalog.getPageLayoutMode(), PdfPageLayout.twoPageRight);
      expect(await catalog.getPageModeValue(), PdfPageMode.useAttachments);
    });

    test('absent PageLayout and PageMode read back as the Table 28 defaults',
        () async {
      final catalog = await roundtrip((doc, catalog) async {});

      expect(await catalog.getPageLayoutMode(), PdfPageLayout.singlePage);
      expect(await catalog.getPageModeValue(), PdfPageMode.useNone);
    });

    test('an unrecognized PageMode falls back to UseNone', () async {
      final catalog = await roundtrip((doc, catalog) async {
        catalog.setPageMode(PdfName.intern('NotAPageMode'));
      });

      expect(await catalog.getPageModeValue(), PdfPageMode.useNone);
    });

    test('Version is written as a name object and read back', () async {
      final catalog = await roundtrip((doc, catalog) async {
        catalog.setVersion(PdfVersion.PDF_1_7);
      });

      expect(await catalog.getVersion(), PdfVersion.PDF_1_7);
      expect(await catalog.pdfRepresentation().nameEntry(PdfCatalog.versionKey),
          PdfName.intern('1.7'));
    });

    test('an unparsable Version reads back as null', () async {
      final catalog = await roundtrip((doc, catalog) async {
        catalog.put(PdfCatalog.versionKey, PdfName.intern('9.9'));
      });

      expect(await catalog.getVersion(), isNull);
    });

    test('OpenAction accepts a destination array', () async {
      final catalog = await roundtrip((doc, catalog) async {
        final page = (await doc.firstPage())!;
        final destination = PdfArray.fromList(<PdfObject>[
          page.pdfRepresentation().indirectHandle()!,
          PdfName.intern('Fit'),
        ]);
        catalog.setOpenAction(destination);
      });

      final openAction = await catalog.getOpenAction();
      expect(openAction, isA<PdfArray>());
      expect(
          await (openAction as PdfArray).nameEntry(1), PdfName.intern('Fit'));
    });

    test('OpenAction accepts an action dictionary', () async {
      final catalog = await roundtrip((doc, catalog) async {
        final action = PdfDictionary();
        action.put(PdfName.type, PdfName.intern('Action'));
        action.put(PdfName.s, PdfName.intern('JavaScript'));
        catalog.setOpenAction(action);
      });

      final openAction = await catalog.getOpenAction();
      expect(openAction, isA<PdfDictionary>());
      expect(await (openAction as PdfDictionary).nameEntry(PdfName.s),
          PdfName.intern('JavaScript'));
    });

    test('OpenAction rejects a value that is neither array nor dictionary', () {
      final catalog = PdfCatalog(PdfDictionary());
      expect(() => catalog.setOpenAction(PdfName.intern('Fit')),
          throwsA(isA<PdfException>()));
      expect(() => catalog.setOpenAction(PdfNumber.fromInt(3)),
          throwsA(isA<PdfException>()));
    });

    test('removeOpenAction drops the entry', () async {
      final catalog = await roundtrip((doc, catalog) async {
        catalog.setOpenAction(PdfDictionary());
        catalog.removeOpenAction();
      });

      expect(await catalog.getOpenAction(), isNull);
    });

    test('AA, URI, SpiderInfo, OCProperties, Perms and Collection roundtrip',
        () async {
      final catalog = await roundtrip((doc, catalog) async {
        final aa = PdfDictionary();
        aa.put(PdfName.intern('WC'), PdfDictionary());
        catalog.setAdditionalActions(aa);

        (await catalog.uriDictionary()).setBase('https://example.org/docs/');

        final spider = PdfDictionary();
        spider.put(PdfName.intern('V'), PdfNumber.fromInt(1));
        catalog.setSpiderInfo(spider);

        final oc = PdfDictionary();
        oc.put(PdfName.intern('OCGs'), PdfArray());
        catalog.setOcProperties(oc);

        final perms = PdfDictionary();
        perms.put(PdfName.intern('DocMDP'), PdfDictionary());
        catalog.setPermissions(perms);

        final collection = PdfDictionary();
        collection.put(PdfName.intern('View'), PdfName.intern('D'));
        catalog.setCollection(collection);
      });

      expect(
          (await catalog.getAdditionalActions())!
              .containsKey(PdfName.intern('WC')),
          isTrue);
      expect(await (await catalog.getUriDictionary())!.getBase(),
          'https://example.org/docs/');
      expect(
          await (await catalog.getSpiderInfo())!
              .numberEntry(PdfName.intern('V')),
          isNotNull);
      expect(
          (await catalog.getOcProperties())!
              .containsKey(PdfName.intern('OCGs')),
          isTrue);
      expect(
          (await catalog.getPermissions())!
              .containsKey(PdfName.intern('DocMDP')),
          isTrue);
      expect(
          await (await catalog.getCollection())!
              .nameEntry(PdfName.intern('View')),
          PdfName.intern('D'));
    });

    test('Lang survives a roundtrip and rejects an empty identifier', () async {
      final catalog = await roundtrip((doc, catalog) async {
        catalog.setLanguage('pt-BR');
      });

      expect(await catalog.getLanguage(), 'pt-BR');
      expect(() => catalog.setLanguage(''), throwsA(isA<PdfException>()));
    });

    test('a catalog without Lang reports an unknown language', () async {
      final catalog = await roundtrip((doc, catalog) async {});
      expect(await catalog.getLanguage(), isNull);
    });

    test('MarkInfo flags survive a roundtrip (Table 321)', () async {
      final catalog = await roundtrip((doc, catalog) async {
        final markInfo = await catalog.markInfo();
        markInfo.setMarked(true).setUserProperties(true).setSuspects(true);
      });

      final markInfo = await catalog.getMarkInfo();
      expect(markInfo, isNotNull);
      expect(await markInfo!.getMarked(), isTrue);
      expect(await markInfo.getUserProperties(), isTrue);
      expect(await markInfo.getSuspects(), isTrue);
    });

    test('absent MarkInfo flags default to false', () async {
      final catalog = await roundtrip((doc, catalog) async {
        await catalog.markInfo();
      });

      final markInfo = await catalog.getMarkInfo();
      expect(await markInfo!.getMarked(), isFalse);
      expect(await markInfo.getUserProperties(), isFalse);
      expect(await markInfo.getSuspects(), isFalse);
    });

    test('Legal attestation counters survive a roundtrip (Table 259)',
        () async {
      final catalog = await roundtrip((doc, catalog) async {
        final legal = await catalog.legalAttestation();
        legal
            .setCount(PdfLegalAttestationEntry.javaScriptActions, 3)
            .setCount(PdfLegalAttestationEntry.nonEmbeddedFonts, 0)
            .setCount(PdfLegalAttestationEntry.devDepGsOP, 7)
            .setOptionalContent(true)
            .setAttestation('Reviewed by the issuer.');
      });

      final legal = await catalog.getLegalAttestation();
      expect(legal, isNotNull);
      expect(
          await legal!.getCount(PdfLegalAttestationEntry.javaScriptActions), 3);
      expect(
          await legal.getCount(PdfLegalAttestationEntry.nonEmbeddedFonts), 0);
      expect(await legal.getCount(PdfLegalAttestationEntry.devDepGsOP), 7);
      expect(
          await legal.getCount(PdfLegalAttestationEntry.movieActions), isNull);
      expect(await legal.getOptionalContent(), isTrue);
      expect(await legal.getAttestation(), 'Reviewed by the issuer.');
    });

    test('a negative Legal counter is rejected', () {
      final legal = PdfLegalAttestation();
      expect(() => legal.setCount(PdfLegalAttestationEntry.launchActions, -1),
          throwsA(isA<PdfException>()));
    });

    test('NeedsRendering survives a roundtrip and defaults to false', () async {
      final enabled = await roundtrip((doc, catalog) async {
        catalog.setNeedsRendering(true);
      });
      expect(await enabled.getNeedsRendering(), isTrue);

      final absent = await roundtrip((doc, catalog) async {});
      expect(await absent.getNeedsRendering(), isFalse);
    });

    test('Extensions and PageLabels survive a roundtrip', () async {
      final catalog = await roundtrip((doc, catalog) async {
        final extensions = PdfDictionary();
        final adbe = PdfDictionary();
        adbe.put(PdfName.intern('BaseVersion'), PdfName.intern('1.7'));
        adbe.put(PdfName.intern('ExtensionLevel'), PdfNumber.fromInt(3));
        extensions.put(PdfName.intern('ADBE'), adbe);
        catalog.setExtensions(extensions);

        final labels = PdfDictionary();
        labels.put(
            PdfName.intern('Nums'),
            PdfArray.fromList(<PdfObject>[
              PdfNumber.fromInt(0),
              PdfDictionary.fromMap({PdfName.s: PdfName.intern('D')}),
            ]));
        catalog.setPageLabels(labels);
      });

      final adbe = await (await catalog.getExtensions())!
          .dictionaryEntry(PdfName.intern('ADBE'));
      expect(await adbe!.nameEntry(PdfName.intern('BaseVersion')),
          PdfName.intern('1.7'));
      expect(
          (await (await catalog.getPageLabels())!
                  .arrayEntry(PdfName.intern('Nums')))!
              .size(),
          2);
    });

    test('Metadata, OutputIntents and Names stay reachable', () async {
      final catalog = await roundtrip((doc, catalog) async {
        await doc.registerDestination(
            'alvo',
            PdfArray.fromList(<PdfObject>[
              (await doc.firstPage())!.pdfRepresentation().indirectHandle()!,
              PdfName.intern('Fit'),
            ]));
        catalog.registerOutputProfile(PdfDictionary.fromMap({
          PdfName.type: PdfName.intern('OutputIntent'),
          PdfName.s: PdfName.intern('GTS_PDFA1'),
          PdfName.intern('OutputConditionIdentifier'): PdfString('sRGB'),
        }));
      });

      expect(await catalog.getNames(), isNotNull);
      expect((await catalog.getOutputIntents())!.size(), 1);
    });
  });
}
