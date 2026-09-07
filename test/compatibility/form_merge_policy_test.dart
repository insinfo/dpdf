import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/editing/pdf_page_assembly.dart';
import 'package:dpdf/src/forms/pdf_acro_form.dart';
import 'package:dpdf/src/forms/fields/pdf_form_field.dart';
import 'package:dpdf/src/forms/fields/pdf_text_form_field.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/annot/pdf_widget_annotation.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';

Future<Uint8List> source(
    {bool signature = false,
    String name = 'nome',
    bool resources = false}) async {
  final bytes = BytesBuilder();
  final doc = CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(bytes));
  final page = await doc.appendBlankPage();
  final widget =
      CraftPdfWidgetAnnotation.fromRect(CraftRectangle(10, 10, 100, 20));
  final form = await CraftPdfAcroForm.getAcroForm(doc, true);
  CraftPdfFormField field;
  if (signature) {
    final dictionary = widget.pdfRepresentation()
      ..put(CraftPdfName.ft, CraftPdfName.sig);
    dictionary.put(
        CraftPdfName.v,
        CraftPdfDictionary()
          ..put(CraftPdfName.contents, CraftPdfString('REMOVETHISCMS')));
    final appearance = CraftPdfStream()
      ..setData(Uint8List.fromList('0 0 10 10 re f'.codeUnits));
    appearance.put(CraftPdfName.type, CraftPdfName('XObject'));
    appearance.put(CraftPdfName.subtype, CraftPdfName('Form'));
    appearance.put(
        CraftPdfName.bBox, CraftRectangle(0, 0, 100, 20).toPdfArray());
    dictionary.put(
        CraftPdfName.ap, CraftPdfDictionary()..put(CraftPdfName.n, appearance));
    field = CraftPdfFormField(dictionary)..setFieldName(name);
  } else {
    field = await CraftPdfTextFormField.createText(doc, name, 'valor', widget);
  }
  if (resources) {
    final typeface = CraftPdfDictionary()
      ..put(CraftPdfName.type, CraftPdfName('Font'))
      ..put(CraftPdfName.subtype, CraftPdfName('Type1'))
      ..put(CraftPdfName('BaseFont'), CraftPdfName('Helvetica'));
    form.pdfRepresentation().put(
        CraftPdfName.dr,
        CraftPdfDictionary()
          ..put(CraftPdfName('Font'),
              CraftPdfDictionary()..put(CraftPdfName('F1'), typeface)));
    form
        .pdfRepresentation()
        .put(CraftPdfName.da, CraftPdfString('/F1 12 Tf 0 g'));
  }
  await form.addField(field, page);
  await doc.close();
  return bytes.toBytes();
}

Future<CraftPdfDocument> open(Uint8List bytes) async {
  final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
  addTearDown(doc.close);
  return doc;
}

void main() {
  test('form merge renames colliding fields and reconnects widget parents',
      () async {
    final input = await source();
    final doc = await open(await PdfPageAssembly.merge(
        [PdfPageSelection(input), PdfPageSelection(input)],
        preserveForms: true));
    final fields = await (await CraftPdfAcroForm.getAcroForm(doc, false))
        .getAllFormFields();
    expect(fields.keys, containsAll(['nome', 'nome_2']));
    for (var index = 1; index <= 2; index++) {
      final page = (await doc.pageAt(index))!;
      final annotations =
          (await page.pdfRepresentation().arrayEntry(CraftPdfName.annots))!;
      expect(annotations.size(), 1);
      final widget = (await annotations.dictionaryEntry(0))!;
      expect(await widget.dictionaryEntry(CraftPdfName.parent), isNotNull);
      expect(await widget.dictionaryEntry(CraftPdfName.p),
          same(page.pdfRepresentation()));
    }
  });
  test('signature policies reject by default and remove CMS before copying',
      () async {
    final input = await source(signature: true);
    await expectLater(
        PdfPageAssembly.merge([PdfPageSelection(input)], preserveForms: true),
        throwsUnsupportedError);
    for (final policy in [
      PdfMergeSignaturePolicy.removeKeepAppearance,
      PdfMergeSignaturePolicy.removeAppearance
    ]) {
      final bytes = await PdfPageAssembly.merge([PdfPageSelection(input)],
          preserveForms: true, signaturePolicy: policy);
      expect(latin1.decode(bytes).contains('REMOVETHISCMS'), isFalse);
      final doc = await open(bytes);
      expect(
          (await (await CraftPdfAcroForm.getAcroForm(doc, false))
              .getAllFormFields()),
          isEmpty);
      final annotations = await (await doc.pageAt(1))!
          .pdfRepresentation()
          .arrayEntry(CraftPdfName.annots);
      expect(annotations?.size() ?? 0,
          policy == PdfMergeSignaturePolicy.removeKeepAppearance ? 1 : 0);
    }
  });
  test('hierarchies, widgetless fields and selected-page widgets survive',
      () async {
    final buffer = BytesBuilder();
    final original =
        CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(buffer));
    final first = await original.appendBlankPage();
    final second = await original.appendBlankPage();
    final form = await CraftPdfAcroForm.getAcroForm(original, true);
    final parent = CraftPdfFormField(CraftPdfDictionary())
      ..setFieldName('group');
    final child =
        await CraftPdfTextFormField.createText(original, 'item', 'kept');
    final one =
        CraftPdfWidgetAnnotation.fromRect(CraftRectangle(10, 10, 100, 20));
    final two =
        CraftPdfWidgetAnnotation.fromRect(CraftRectangle(10, 10, 100, 20));
    await child.addKid(one);
    await child.addKid(two);
    await first.addAnnotation(one);
    await second.addAnnotation(two);
    await parent.addChildField(child);
    await form.addField(parent);
    await form.addField(
        await CraftPdfTextFormField.createText(original, 'hidden', 'data'));
    await original.close();
    final colliding = await source(name: 'group.item');
    final doc = await open(await PdfPageAssembly.merge([
      PdfPageSelection(colliding),
      PdfPageSelection(buffer.toBytes(), pages: [2])
    ], preserveForms: true));
    final fields = await (await CraftPdfAcroForm.getAcroForm(doc, false))
        .getAllFormFields();
    expect(fields.keys, containsAll(['group.item', 'group_2.item', 'hidden']));
    expect((await fields['group_2.item']!.getWidgets()).length, 1);
    expect((await fields['hidden']!.getWidgets()), isEmpty);
  });

  test('default appearance font names follow merged resource collisions',
      () async {
    final bytes = await source(resources: true);
    final doc = await open(await PdfPageAssembly.merge(
        [PdfPageSelection(bytes), PdfPageSelection(bytes)],
        preserveForms: true));
    final form = (await doc
        .rootCatalog()
        .pdfRepresentation()
        .dictionaryEntry(CraftPdfName.acroForm))!;
    final resources = await form.dictionaryEntry(CraftPdfName.dr);
    expect((await resources!.dictionaryEntry(CraftPdfName('Font')))!.size(), 2);
    final fields = (await form.arrayEntry(CraftPdfName.fields))!;
    final renamed = (await fields.dictionaryEntry(1))!;
    expect((await renamed.stringEntry(CraftPdfName.da))!.decodeMappingText(),
        '/F1_2 12 Tf 0 g');
  });

  test('repeated selected pages share one field with independent widgets',
      () async {
    final input = await source();
    final doc = await open(await PdfPageAssembly.merge([
      PdfPageSelection(input, pages: [1, 1])
    ], preserveForms: true));
    final form = await CraftPdfAcroForm.getAcroForm(doc, false);
    final fields = await form.getAllFormFields();
    expect(fields.length, 1);
    final widgets = await fields['nome']!.getWidgets();
    expect(widgets.length, 2);
    expect(
        identical(
            widgets[0].pdfRepresentation(), widgets[1].pdfRepresentation()),
        isFalse);
    for (var index = 1; index <= 2; index++) {
      final page = (await doc.pageAt(index))!.pdfRepresentation();
      expect((await page.arrayEntry(CraftPdfName.annots))!.size(), 1);
      expect(
          await widgets[index - 1]
              .pdfRepresentation()
              .dictionaryEntry(CraftPdfName.p),
          same(page));
    }
  });

  test('flatten enforces explicit signature disposition', () async {
    final input = await source(signature: true);
    await expectLater(
        PdfPageAssembly.merge([PdfPageSelection(input)],
            mode: PdfMergeMode.flatten),
        throwsUnsupportedError);
    await expectLater(
        PdfPageAssembly.merge([PdfPageSelection(input)],
            mode: PdfMergeMode.flatten,
            signaturePolicy: PdfMergeSignaturePolicy.keepInvalid),
        throwsUnsupportedError);
    for (final policy in [
      PdfMergeSignaturePolicy.removeKeepAppearance,
      PdfMergeSignaturePolicy.removeAppearance
    ]) {
      final bytes = await PdfPageAssembly.merge([PdfPageSelection(input)],
          mode: PdfMergeMode.flatten, signaturePolicy: policy);
      expect(latin1.decode(bytes).contains('REMOVETHISCMS'), isFalse);
      final doc = await open(bytes);
      expect(
          await doc
              .rootCatalog()
              .pdfRepresentation()
              .dictionaryEntry(CraftPdfName.acroForm),
          isNull);
      final page = (await doc.pageAt(1))!;
      expect(await page.pdfRepresentation().arrayEntry(CraftPdfName.annots),
          isNull);
      final resources = await page
          .pdfRepresentation()
          .dictionaryEntry(CraftPdfName.resources);
      final objects = await resources?.dictionaryEntry(CraftPdfName('XObject'));
      expect(objects?.size() ?? 0,
          policy == PdfMergeSignaturePolicy.removeKeepAppearance ? 2 : 1);
    }
  });

  test('keepInvalid retains signature value only under explicit policy',
      () async {
    final input = await source(signature: true);
    final doc = await open(await PdfPageAssembly.merge(
        [PdfPageSelection(input)],
        preserveForms: true,
        signaturePolicy: PdfMergeSignaturePolicy.keepInvalid));
    final field =
        await (await CraftPdfAcroForm.getAcroForm(doc, false)).getField('nome');
    expect(await field!.pdfRepresentation().dictionaryEntry(CraftPdfName.v),
        isNotNull);
  });
}
