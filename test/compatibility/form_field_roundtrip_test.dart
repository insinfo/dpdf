import 'package:dpdf/dpdf.dart';
import 'dart:typed_data';
import 'package:test/test.dart';

Future<CraftPdfDocument> roundtrip(
    Future<void> Function(CraftPdfDocument, CraftPdfPage, CraftPdfAcroForm)
        build) async {
  final bytes = BytesBuilder();
  final doc =
      await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(bytes));
  final page = await doc.appendBlankPage();
  final form = await CraftPdfAcroForm.getAcroForm(doc, true);
  await build(doc, page, form);
  await doc.close();
  final reopened =
      await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes.toBytes()));
  addTearDown(reopened.close);
  return reopened;
}

CraftPdfWidgetAnnotation widget() =>
    CraftPdfWidgetAnnotation.fromRect(CraftRectangle(20, 20, 200, 24));
Future<CraftPdfFormField> field(CraftPdfDocument doc, String name) async =>
    (await (await CraftPdfAcroForm.getAcroForm(doc, false)).getField(name))!;

void main() {
  test('text and multiline/password/readonly flags survive roundtrip',
      () async {
    final result = await roundtrip((doc, page, form) async {
      final text = await CraftPdfTextFormField.createText(
          doc, 'nome', 'Isaque Neves', widget());
      await form.addField(text, page);
      final notes = await CraftPdfTextFormField.createMultilineText(
          doc, 'notas', 'linha um', widget());
      notes.setMaxLen(120);
      await form.addField(notes, page);
      final password =
          await CraftPdfTextFormField.createText(doc, 'senha', '', widget());
      await password.setPassword(true);
      await password.setFieldFlag(CraftPdfFormField.ffReadOnly, true);
      await form.addField(password, page);
    });
    expect(
        (await (await field(result, 'nome'))
                .pdfRepresentation()
                .stringEntry(CraftPdfName.v))!
            .decodeMappingText(),
        'Isaque Neves');
    final notes = await field(result, 'notas') as CraftPdfTextFormField;
    expect(await notes.isMultiline(), isTrue);
    expect(await notes.getMaxLen(), 120);
    final password = await field(result, 'senha') as CraftPdfTextFormField;
    expect(await password.isPassword(), isTrue);
    expect(await password.getFieldFlag(CraftPdfFormField.ffReadOnly), isTrue);
  });

  test('loaded text value can be updated and serialized again', () async {
    final original = await roundtrip((doc, page, form) async {
      await form.addField(
          await CraftPdfTextFormField.createText(
              doc, 'campo', 'antes', widget()),
          page);
    });
    final bytes = original.inputReader()!.getOriginalBytes()!;
    final output = BytesBuilder();
    final editing = CraftPdfDocument(
        reader: CraftPdfReader.fromBytes(bytes),
        writer: CraftPdfWriter.fromBytesBuilder(output));
    await editing.load();
    (await field(editing, 'campo')).setValue('depois');
    await editing.close();
    final result =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(output.toBytes()));
    addTearDown(result.close);
    expect(
        (await (await field(result, 'campo'))
                .pdfRepresentation()
                .stringEntry(CraftPdfName.v))!
            .decodeMappingText(),
        'depois');
  });

  test('editable combo flag and free value survive roundtrip', () async {
    final result = await roundtrip((doc, page, form) async {
      final choice = CraftPdfChoiceFormField(
          CraftPdfDictionary()..put(CraftPdfName.ft, CraftPdfName.ch))
        ..setFieldName('livre');
      await choice.setFieldFlag(CraftPdfChoiceFormField.ffCombo, true);
      await choice.setFieldFlag(CraftPdfChoiceFormField.ffEdit, true);
      (await choice.getOptions()).add(CraftPdfString('a'));
      await choice.setListSelected(['free'], generateAppearance: false);
      await choice.addKid(widget());
      await form.addField(choice, page);
    });
    final choice = await field(result, 'livre') as CraftPdfChoiceFormField;
    expect(await choice.isEdit(), isTrue);
    expect(
        (await choice.pdfRepresentation().stringEntry(CraftPdfName.v))!
            .decodeMappingText(),
        'free');
  });

  test('checkbox name states survive roundtrip', () async {
    final result = await roundtrip((doc, page, form) async {
      for (final name in ['aceito', 'recuso']) {
        final dictionary = widget().pdfRepresentation();
        dictionary.put(CraftPdfName.ft, CraftPdfName.btn);
        final checkbox = CraftPdfButtonFormField(dictionary)
          ..setFieldName(name);
        checkbox.setValue(CraftPdfName(name == 'aceito' ? 'Yes' : 'Off'));
        await form.addField(checkbox, page);
      }
    });
    expect(
        await (await field(result, 'aceito'))
            .pdfRepresentation()
            .nameEntry(CraftPdfName.v),
        CraftPdfName('Yes'));
    expect(
        await (await field(result, 'recuso'))
            .pdfRepresentation()
            .nameEntry(CraftPdfName.v),
        CraftPdfName('Off'));
  });

  for (final multi in [false, true]) {
    test(
        'choice export values and labels survive ${multi ? "multiple" : "single"} selection',
        () async {
      final result = await roundtrip((doc, page, form) async {
        final dictionary = CraftPdfDictionary()
          ..put(CraftPdfName.ft, CraftPdfName.ch);
        final choice = CraftPdfChoiceFormField(dictionary)
          ..setFieldName('cidade');
        await choice.setFieldFlag(
            multi
                ? CraftPdfChoiceFormField.ffMultiSelect
                : CraftPdfChoiceFormField.ffCombo,
            true);
        final options = await choice.getOptions();
        for (final item in [
          ('rio', 'Rio das Ostras'),
          ('macae', 'Macae'),
          ('campos', 'Campos')
        ]) {
          options.add(CraftPdfArray()
            ..add(CraftPdfString(item.$1))
            ..add(CraftPdfString(item.$2)));
        }
        await choice.addKid(widget());
        await choice.setListSelected(multi ? ['rio', 'campos'] : ['macae'],
            generateAppearance: false);
        await form.addField(choice, page);
      });
      final choice = await field(result, 'cidade') as CraftPdfChoiceFormField;
      expect((await choice.getOptions()).size(), 3);
      expect((await (await choice.getOptions()).arrayEntry(0))!.size(), 2);
      final indices = await choice.getIndices();
      expect(indices?.size(), multi ? 2 : 1);
      if (!multi) {
        expect(
            (await choice.pdfRepresentation().stringEntry(CraftPdfName.v))!
                .decodeMappingText(),
            'macae');
      } else {
        expect(
            (await choice.pdfRepresentation().arrayEntry(CraftPdfName.v))!
                .size(),
            2);
      }
    });
  }

  test('radio group remains one field with two widgets and one selection',
      () async {
    final result = await roundtrip((doc, page, form) async {
      final radio =
          CraftPdfButtonFormField.createRadioGroup(doc, 'opcao', 'nao');
      for (final option in ['sim', 'nao']) {
        await CraftPdfButtonFormField.createRadioButton(
            doc, CraftRectangle(20, 20, 16, 16), radio, option);
      }
      await form.addField(radio, page);
    });
    final form = await CraftPdfAcroForm.getAcroForm(result, false);
    expect((await form.getAllFormFields()).length, 1);
    final radio = (await form.getField('opcao'))!;
    expect(await radio.pdfRepresentation().nameEntry(CraftPdfName.v),
        CraftPdfName('nao'));
    final widgets = await radio.getWidgets();
    expect(widgets.length, 2);
    expect(await widgets[0].pdfRepresentation().nameEntry(CraftPdfName.as),
        CraftPdfName('Off'));
    expect(await widgets[1].pdfRepresentation().nameEntry(CraftPdfName.as),
        CraftPdfName('nao'));
    for (final widget in widgets) {
      final appearance =
          await widget.pdfRepresentation().dictionaryEntry(CraftPdfName.ap);
      expect(appearance, isNotNull);
      expect((await appearance!.dictionaryEntry(CraftPdfName.n))!.size(), 2);
    }
    final page = await result.pageAt(1);
    expect(
        (await page!.pdfRepresentation().arrayEntry(CraftPdfName.annots))!
            .size(),
        2);
  });
}
