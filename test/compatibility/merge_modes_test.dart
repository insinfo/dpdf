import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/dpdf.dart';

import 'changelog_merge_regression_test.dart' show source;
import 'form_merge_policy_test.dart' as forms;

Future<Uint8List> links() async {
  final out = BytesBuilder();
  final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(out));
  final a = await doc.appendBlankPage(), b = await doc.appendBlankPage();
  final destination =
      PdfArray.fromList([b.pdfRepresentation(), PdfName('Fit')]);
  doc.rootCatalog().pdfRepresentation().put(
      PdfName('Dests'),
      PdfDictionary()
        ..put(PdfName('target'),
            PdfDictionary()..put(PdfName('D'), destination)));
  a.pdfRepresentation().put(
      PdfName.annots,
      PdfArray.withObject(PdfDictionary()
        ..put(PdfName.subtype, PdfName('Link'))
        ..put(PdfName('Rect'), PdfArray.fromDoubles([0, 0, 100, 20]))
        ..put(PdfName('Dest'), PdfString('target'))));
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
      final doc = await PdfDocument.open(PdfReader.fromBytes(output));
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
      final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final group = PdfDictionary()
        ..put(PdfName.type, PdfName('OCG'))
        ..put(PdfName('Name'), PdfString('Shared name'))
        ..attachToDocument(doc);
      for (var i = 0; i < 3; i++) {
        final page = await doc.appendBlankPage();
        page.pdfRepresentation().put(
            PdfName.resources,
            PdfDictionary()
              ..put(PdfName('Properties'),
                  PdfDictionary()..put(PdfName('Layer'), group)));
      }
      final catalog = doc.rootCatalog().pdfRepresentation();
      catalog.put(
          PdfName('OCProperties'),
          PdfDictionary()
            ..put(PdfName('OCGs'), PdfArray.withObject(group))
            ..put(
                PdfName('D'),
                PdfDictionary()
                  ..put(PdfName('OFF'), PdfArray.withObject(group))
                  ..put(PdfName('Order'), PdfArray.withObject(group))));
      catalog.put(
          PdfName('PageLabels'),
          PdfDictionary()
            ..put(
                PdfName('Nums'),
                PdfArray.fromList([
                  PdfNumber.fromInt(0),
                  PdfDictionary()
                    ..put(PdfName('S'), PdfName('r'))
                    ..put(PdfName('P'), PdfString('A-'))
                    ..put(PdfName('St'), PdfNumber.fromInt(4))
                ])));
      await doc.close();
      return bytes.takeBytes();
    }

    final bytes = await input();
    final output = await PdfPageAssembly.merge([
      PdfPageSelection(bytes, pages: [3, 1]),
      PdfPageSelection(bytes, pages: [2])
    ], preserveLayers: true, preservePageLabels: true);
    final doc = await PdfDocument.open(PdfReader.fromBytes(output));
    try {
      final catalog = doc.rootCatalog().pdfRepresentation();
      final layers = (await catalog.dictionaryEntry(PdfName('OCProperties')))!;
      final groups = (await layers.arrayEntry(PdfName('OCGs')))!;
      expect(groups.size(), 2);
      expect(await groups.dictionaryEntry(0),
          isNot(same(await groups.dictionaryEntry(1))));
      for (var p = 1; p <= 3; p++) {
        final resources = (await (await doc.pageAt(p))!
            .pdfRepresentation()
            .dictionaryEntry(PdfName.resources))!;
        final props = (await resources.dictionaryEntry(PdfName('Properties')))!;
        expect(await props.dictionaryEntry(PdfName('Layer')),
            same(await groups.dictionaryEntry(p == 3 ? 1 : 0)));
      }
      final rules =
          (await (await catalog.dictionaryEntry(PdfName('PageLabels')))!
              .arrayEntry(PdfName('Nums')))!;
      expect([
        for (var i = 1; i < rules.size(); i += 2)
          (await (await rules.dictionaryEntry(i))!.numberEntry(PdfName('St')))!
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
    final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
    final page = await doc.appendBlankPage();
    final appearance =
        PdfStream.withBytes(Uint8List.fromList('0 0 10 10 re f'.codeUnits))
          ..put(PdfName.type, PdfName.xObject)
          ..put(PdfName.subtype, PdfName.form)
          ..put(PdfName.bBox, PdfArray.fromDoubles([0, 0, 10, 10]));
    final annotation = PdfDictionary()
      ..put(PdfName.subtype, PdfName('Widget'))
      ..put(PdfName('Rect'), PdfArray.fromDoubles([20, 30, 120, 80]))
      ..put(PdfName('AP'), PdfDictionary()..put(PdfName('N'), appearance));
    page
        .pdfRepresentation()
        .put(PdfName.annots, PdfArray.withObject(annotation));
    doc
        .rootCatalog()
        .pdfRepresentation()
        .put(PdfName('AcroForm'), PdfDictionary());
    await doc.close();
    final output = await PdfPageAssembly.merge(
        [PdfPageSelection(bytes.takeBytes())],
        mode: PdfMergeMode.flatten);
    final read = await PdfDocument.open(PdfReader.fromBytes(output));
    try {
      final page = (await read.pageAt(1))!;
      expect(page.pdfRepresentation().containsKey(PdfName.annots), isFalse);
      expect(
          read
              .rootCatalog()
              .pdfRepresentation()
              .containsKey(PdfName('AcroForm')),
          isFalse);
      expect(String.fromCharCodes(await page.contentPayload()),
          contains('/Appearance0 Do'));
      final forms = await (await page.resourceDirectory())
          .pdfRepresentation()
          .dictionaryEntry(PdfName.xObject);
      expect(await forms!.streamEntry(PdfName('Appearance0')), isNotNull);
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
    final doc = await PdfDocument.open(PdfReader.fromBytes(bytes));
    try {
      expect(doc.pageTotal(), 2);
      expect(await PdfTextExtraction.fromPage((await doc.pageAt(1))!),
          contains('Source 1'));
      final resources = await (await doc.pageAt(1))!.resourceDirectory();
      expect(
          await resources.pdfRepresentation().dictionaryEntry(PdfName.xObject),
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
    final doc = await PdfDocument.open(PdfReader.fromBytes(bytes));
    try {
      final page = (await doc.pageAt(2))!;
      final annotations =
          (await page.pdfRepresentation().arrayEntry(PdfName.annots))!;
      final annotation = (await annotations.dictionaryEntry(0))!;
      final dest = (await annotation.arrayEntry(PdfName('Dest')))!;
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
