import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pdfcraft/pdfcraft.dart';

import 'changelog_merge_regression_test.dart' show source;
import 'form_merge_policy_test.dart' as forms;

Future<Uint8List> links() async {
  final out = BytesBuilder();
  final doc =
      await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(out));
  final a = await doc.appendBlankPage(), b = await doc.appendBlankPage();
  final destination =
      CraftPdfArray.fromList([b.pdfRepresentation(), CraftPdfName('Fit')]);
  doc.rootCatalog().pdfRepresentation().put(
      CraftPdfName('Dests'),
      CraftPdfDictionary()
        ..put(CraftPdfName('target'),
            CraftPdfDictionary()..put(CraftPdfName('D'), destination)));
  a.pdfRepresentation().put(
      CraftPdfName.annots,
      CraftPdfArray.withObject(CraftPdfDictionary()
        ..put(CraftPdfName.subtype, CraftPdfName('Link'))
        ..put(CraftPdfName('Rect'), CraftPdfArray.fromDoubles([0, 0, 100, 20]))
        ..put(CraftPdfName('Dest'), CraftPdfString('target'))));
  await doc.close();
  return out.takeBytes();
}

void main() {
  test(
      'flatten signature policies explicitly remove CMS and optionally appearance',
      () async {
    final bytes = await forms.source(signature: true);
    for (final policy in [
      PdfMergeSignaturePolicy.reject,
      PdfMergeSignaturePolicy.keepInvalid
    ]) {
      await expectLater(
          PdfPageAssembly.merge([PdfPageSelection(bytes)],
              mode: PdfMergeMode.flatten, signaturePolicy: policy),
          throwsUnsupportedError);
    }
    for (final policy in [
      PdfMergeSignaturePolicy.removeKeepAppearance,
      PdfMergeSignaturePolicy.removeAppearance
    ]) {
      final output = await PdfPageAssembly.merge([PdfPageSelection(bytes)],
          mode: PdfMergeMode.flatten, signaturePolicy: policy);
      expect(String.fromCharCodes(output), isNot(contains('REMOVETHISCMS')));
      final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(output));
      try {
        final content =
            String.fromCharCodes(await (await doc.pageAt(1))!.contentPayload());
        expect(content.contains('/Appearance0 Do'),
            policy == PdfMergeSignaturePolicy.removeKeepAppearance);
      } finally {
        await doc.close();
      }
    }
  });

  test('layers and page labels survive reordering and separate sources',
      () async {
    Future<Uint8List> input() async {
      final bytes = BytesBuilder();
      final doc =
          await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(bytes));
      final group = CraftPdfDictionary()
        ..put(CraftPdfName.type, CraftPdfName('OCG'))
        ..put(CraftPdfName('Name'), CraftPdfString('Shared name'))
        ..attachToDocument(doc);
      for (var i = 0; i < 3; i++) {
        final page = await doc.appendBlankPage();
        page.pdfRepresentation().put(
            CraftPdfName.resources,
            CraftPdfDictionary()
              ..put(CraftPdfName('Properties'),
                  CraftPdfDictionary()..put(CraftPdfName('Layer'), group)));
      }
      final catalog = doc.rootCatalog().pdfRepresentation();
      catalog.put(
          CraftPdfName('OCProperties'),
          CraftPdfDictionary()
            ..put(CraftPdfName('OCGs'), CraftPdfArray.withObject(group))
            ..put(
                CraftPdfName('D'),
                CraftPdfDictionary()
                  ..put(CraftPdfName('OFF'), CraftPdfArray.withObject(group))
                  ..put(
                      CraftPdfName('Order'), CraftPdfArray.withObject(group))));
      catalog.put(
          CraftPdfName('PageLabels'),
          CraftPdfDictionary()
            ..put(
                CraftPdfName('Nums'),
                CraftPdfArray.fromList([
                  CraftPdfNumber.fromInt(0),
                  CraftPdfDictionary()
                    ..put(CraftPdfName('S'), CraftPdfName('r'))
                    ..put(CraftPdfName('P'), CraftPdfString('A-'))
                    ..put(CraftPdfName('St'), CraftPdfNumber.fromInt(4))
                ])));
      await doc.close();
      return bytes.takeBytes();
    }

    final bytes = await input();
    final output = await PdfPageAssembly.merge([
      PdfPageSelection(bytes, pages: [3, 1]),
      PdfPageSelection(bytes, pages: [2])
    ], preserveLayers: true, preservePageLabels: true);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(output));
    try {
      final catalog = doc.rootCatalog().pdfRepresentation();
      final layers =
          (await catalog.dictionaryEntry(CraftPdfName('OCProperties')))!;
      final groups = (await layers.arrayEntry(CraftPdfName('OCGs')))!;
      expect(groups.size(), 2);
      expect(await groups.dictionaryEntry(0),
          isNot(same(await groups.dictionaryEntry(1))));
      for (var p = 1; p <= 3; p++) {
        final resources = (await (await doc.pageAt(p))!
            .pdfRepresentation()
            .dictionaryEntry(CraftPdfName.resources))!;
        final props =
            (await resources.dictionaryEntry(CraftPdfName('Properties')))!;
        expect(await props.dictionaryEntry(CraftPdfName('Layer')),
            same(await groups.dictionaryEntry(p == 3 ? 1 : 0)));
      }
      final rules =
          (await (await catalog.dictionaryEntry(CraftPdfName('PageLabels')))!
              .arrayEntry(CraftPdfName('Nums')))!;
      expect([
        for (var i = 1; i < rules.size(); i += 2)
          (await (await rules.dictionaryEntry(i))!
                  .numberEntry(CraftPdfName('St')))!
              .intValue()
      ], [
        6,
        4,
        5
      ]);
    } finally {
      await doc.close();
    }
  });

  test('flatten retains annotation normal appearance and removes interaction',
      () async {
    final bytes = BytesBuilder();
    final doc =
        await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(bytes));
    final page = await doc.appendBlankPage();
    final appearance =
        CraftPdfStream.withBytes(Uint8List.fromList('0 0 10 10 re f'.codeUnits))
          ..put(CraftPdfName.type, CraftPdfName.xObject)
          ..put(CraftPdfName.subtype, CraftPdfName.form)
          ..put(CraftPdfName.bBox, CraftPdfArray.fromDoubles([0, 0, 10, 10]));
    final annotation = CraftPdfDictionary()
      ..put(CraftPdfName.subtype, CraftPdfName('Widget'))
      ..put(CraftPdfName('Rect'), CraftPdfArray.fromDoubles([20, 30, 120, 80]))
      ..put(CraftPdfName('AP'),
          CraftPdfDictionary()..put(CraftPdfName('N'), appearance));
    page
        .pdfRepresentation()
        .put(CraftPdfName.annots, CraftPdfArray.withObject(annotation));
    doc
        .rootCatalog()
        .pdfRepresentation()
        .put(CraftPdfName('AcroForm'), CraftPdfDictionary());
    await doc.close();
    final output = await PdfPageAssembly.merge(
        [PdfPageSelection(bytes.takeBytes())],
        mode: PdfMergeMode.flatten);
    final read = await CraftPdfDocument.open(CraftPdfReader.fromBytes(output));
    try {
      final page = (await read.pageAt(1))!;
      expect(
          page.pdfRepresentation().containsKey(CraftPdfName.annots), isFalse);
      expect(
          read
              .rootCatalog()
              .pdfRepresentation()
              .containsKey(CraftPdfName('AcroForm')),
          isFalse);
      expect(String.fromCharCodes(await page.contentPayload()),
          contains('/Appearance0 Do'));
      final forms = await (await page.resourceDirectory())
          .pdfRepresentation()
          .dictionaryEntry(CraftPdfName.xObject);
      expect(await forms!.streamEntry(CraftPdfName('Appearance0')), isNotNull);
    } finally {
      await read.close();
    }
  });
  test(
      'flatten missing visible appearance fails instead of silently discarding',
      () async {
    await expectLater(
        PdfPageAssembly.merge([PdfPageSelection(await links())],
            mode: PdfMergeMode.flatten, resolveNamedDestinations: true),
        throwsUnsupportedError);
  });

  test('flatten draws inherited source through isolated form', () async {
    final bytes = await PdfPageAssembly.merge(
        [PdfPageSelection(await source())],
        mode: PdfMergeMode.flatten);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      expect(doc.pageTotal(), 2);
      expect(await PdfTextExtraction.fromPage((await doc.pageAt(1))!),
          contains('Source 1'));
      final resources = await (await doc.pageAt(1))!.resourceDirectory();
      expect(
          await resources
              .pdfRepresentation()
              .dictionaryEntry(CraftPdfName.xObject),
          isNotNull);
    } finally {
      await doc.close();
    }
  });
  test(
      'named link resolves inline dictionary and targets reordered imported page',
      () async {
    final bytes = await PdfPageAssembly.merge([
      PdfPageSelection(await links(), pages: [2, 1])
    ], includeAnnotations: true, resolveNamedDestinations: true);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      final page = (await doc.pageAt(2))!;
      final annotations =
          (await page.pdfRepresentation().arrayEntry(CraftPdfName.annots))!;
      final annotation = (await annotations.dictionaryEntry(0))!;
      final dest = (await annotation.arrayEntry(CraftPdfName('Dest')))!;
      expect(await dest.dictionaryEntry(0),
          same((await doc.pageAt(1))!.pdfRepresentation()));
    } finally {
      await doc.close();
    }
  });
  test('named link omitted destination rejected', () async {
    await expectLater(
        PdfPageAssembly.merge([
          PdfPageSelection(await links(), pages: [1])
        ], includeAnnotations: true, resolveNamedDestinations: true),
        throwsUnsupportedError);
  });
  test('odd named destination array rejected when resolution enabled',
      () async {
    await expectLater(
        PdfPageAssembly.merge(
            [PdfPageSelection(await source(destinations: 'odd'))],
            resolveNamedDestinations: true),
        throwsFormatException);
  });
}
