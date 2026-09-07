import 'package:dpdf/dpdf.dart';
import 'dart:typed_data';
import 'package:test/test.dart';

Future<PdfDocument> roundtrip(
    Future<void> Function(PdfDocument, PdfPage, PdfAcroForm) build) async {
  final bytes = BytesBuilder();
  final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
  final page = await doc.appendBlankPage();
  final form = await PdfAcroForm.getAcroForm(doc, true);
  await build(doc, page, form);
  await doc.close();
  final reopened = await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
  addTearDown(reopened.close);
  return reopened;
}

PdfWidgetAnnotation widget() =>
    PdfWidgetAnnotation.fromRect(Rectangle(20, 20, 200, 24));
Future<PdfFormField> field(PdfDocument doc, String name) async =>
    (await (await PdfAcroForm.getAcroForm(doc, false)).getField(name))!;

void main() {
  test('text and multiline/password/readonly flags survive roundtrip',
      () async {
    final result = await roundtrip((doc, page, form) async {
      final text = await PdfTextFormField.createText(
          doc, 'nome', 'Isaque Neves', widget());
      await form.addField(text, page);
      final notes = await PdfTextFormField.createMultilineText(
          doc, 'notas', 'linha um', widget());
      notes.setMaxLen(120);
      await form.addField(notes, page);
      final password =
          await PdfTextFormField.createText(doc, 'senha', '', widget());
      await password.setPassword(true);
      await password.setFieldFlag(PdfFormField.ffReadOnly, true);
      await form.addField(password, page);
    });
    expect(
        (await (await field(result, 'nome'))
                .pdfRepresentation()
                .stringEntry(PdfName.v))!
            .decodeMappingText(),
        'Isaque Neves');
    final notes = await field(result, 'notas') as PdfTextFormField;
    expect(await notes.isMultiline(), isTrue);
    expect(await notes.getMaxLen(), 120);
    final password = await field(result, 'senha') as PdfTextFormField;
    expect(await password.isPassword(), isTrue);
    expect(await password.getFieldFlag(PdfFormField.ffReadOnly), isTrue);
  });

  test('loaded text value can be updated and serialized again', () async {
    final original = await roundtrip((doc, page, form) async {
      await form.addField(
          await PdfTextFormField.createText(doc, 'campo', 'antes', widget()),
          page);
    });
    final bytes = original.inputReader()!.getOriginalBytes()!;
    final output = BytesBuilder();
    final editing = PdfDocument(
        reader: PdfReader.fromBytes(bytes),
        writer: PdfWriter.fromBytesBuilder(output));
    await editing.load();
    (await field(editing, 'campo')).setValue('depois');
    await editing.close();
    final result =
        await PdfDocument.open(PdfReader.fromBytes(output.toBytes()));
    addTearDown(result.close);
    expect(
        (await (await field(result, 'campo'))
                .pdfRepresentation()
                .stringEntry(PdfName.v))!
            .decodeMappingText(),
        'depois');
  });

  test('editable combo flag and free value survive roundtrip', () async {
    final result = await roundtrip((doc, page, form) async {
      final choice =
          PdfChoiceFormField(PdfDictionary()..put(PdfName.ft, PdfName.ch))
            ..setFieldName('livre');
      await choice.setFieldFlag(PdfChoiceFormField.ffCombo, true);
      await choice.setFieldFlag(PdfChoiceFormField.ffEdit, true);
      (await choice.getOptions()).add(PdfString('a'));
      await choice.setListSelected(['free'], generateAppearance: false);
      await choice.addKid(widget());
      await form.addField(choice, page);
    });
    final choice = await field(result, 'livre') as PdfChoiceFormField;
    expect(await choice.isEdit(), isTrue);
    expect(
        (await choice.pdfRepresentation().stringEntry(PdfName.v))!
            .decodeMappingText(),
        'free');
  });

  test('checkbox name states survive roundtrip', () async {
    final result = await roundtrip((doc, page, form) async {
      for (final name in ['aceito', 'recuso']) {
        final dictionary = widget().pdfRepresentation();
        dictionary.put(PdfName.ft, PdfName.btn);
        final checkbox = PdfButtonFormField(dictionary)..setFieldName(name);
        checkbox.setValue(PdfName(name == 'aceito' ? 'Yes' : 'Off'));
        await form.addField(checkbox, page);
      }
    });
    expect(
        await (await field(result, 'aceito'))
            .pdfRepresentation()
            .nameEntry(PdfName.v),
        PdfName('Yes'));
    expect(
        await (await field(result, 'recuso'))
            .pdfRepresentation()
            .nameEntry(PdfName.v),
        PdfName('Off'));
  });

  for (final multi in [false, true]) {
    test(
        'choice export values and labels survive ${multi ? "multiple" : "single"} selection',
        () async {
      final result = await roundtrip((doc, page, form) async {
        final dictionary = PdfDictionary()..put(PdfName.ft, PdfName.ch);
        final choice = PdfChoiceFormField(dictionary)..setFieldName('cidade');
        await choice.setFieldFlag(
            multi
                ? PdfChoiceFormField.ffMultiSelect
                : PdfChoiceFormField.ffCombo,
            true);
        final options = await choice.getOptions();
        for (final item in [
          ('rio', 'Rio das Ostras'),
          ('macae', 'Macae'),
          ('campos', 'Campos')
        ]) {
          options.add(PdfArray()
            ..add(PdfString(item.$1))
            ..add(PdfString(item.$2)));
        }
        await choice.addKid(widget());
        await choice.setListSelected(multi ? ['rio', 'campos'] : ['macae'],
            generateAppearance: false);
        await form.addField(choice, page);
      });
      final choice = await field(result, 'cidade') as PdfChoiceFormField;
      expect((await choice.getOptions()).size(), 3);
      expect((await (await choice.getOptions()).arrayEntry(0))!.size(), 2);
      final indices = await choice.getIndices();
      expect(indices?.size(), multi ? 2 : 1);
      if (!multi) {
        expect(
            (await choice.pdfRepresentation().stringEntry(PdfName.v))!
                .decodeMappingText(),
            'macae');
      } else {
        expect((await choice.pdfRepresentation().arrayEntry(PdfName.v))!.size(),
            2);
      }
    });
  }

  test('radio group remains one field with two widgets and one selection',
      () async {
    final result = await roundtrip((doc, page, form) async {
      final radio = PdfButtonFormField.createRadioGroup(doc, 'opcao', 'nao');
      for (final option in ['sim', 'nao']) {
        await PdfButtonFormField.createRadioButton(
            doc, Rectangle(20, 20, 16, 16), radio, option);
      }
      await form.addField(radio, page);
    });
    final form = await PdfAcroForm.getAcroForm(result, false);
    expect((await form.getAllFormFields()).length, 1);
    final radio = (await form.getField('opcao'))!;
    expect(
        await radio.pdfRepresentation().nameEntry(PdfName.v), PdfName('nao'));
    final widgets = await radio.getWidgets();
    expect(widgets.length, 2);
    expect(await widgets[0].pdfRepresentation().nameEntry(PdfName.as),
        PdfName('Off'));
    expect(await widgets[1].pdfRepresentation().nameEntry(PdfName.as),
        PdfName('nao'));
    for (final widget in widgets) {
      final appearance =
          await widget.pdfRepresentation().dictionaryEntry(PdfName.ap);
      expect(appearance, isNotNull);
      expect((await appearance!.dictionaryEntry(PdfName.n))!.size(), 2);
    }
    final page = await result.pageAt(1);
    expect((await page!.pdfRepresentation().arrayEntry(PdfName.annots))!.size(),
        2);
  });
}
