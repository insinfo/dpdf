import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/tagging/pdf_mcr.dart';
import 'package:dpdf/src/kernel/pdf/tagging/pdf_obj_ref.dart';
import 'package:dpdf/src/kernel/pdf/tagging/pdf_struct_elem.dart';
import 'package:dpdf/src/kernel/pdf/tagging/standard_roles.dart';
import 'package:dpdf/src/kernel/pdf/tagging/tag_tree_pointer.dart';
import 'package:dpdf/src/kernel/pdf/tagutils/accessibility_properties.dart';
import 'package:dpdf/src/kernel/pdf/tagutils/pdf_structure_attributes.dart';
import 'package:dpdf/src/kernel/pdf/tagutils/standard_attribute_owners.dart';
import 'package:test/test.dart';

void main() {
  group('Tagged document round trip', () {
    test('Marked content is written and found again through the parent tree',
        () async {
      final bytes = await _buildTaggedDocument();

      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      final root = await document.loadStructureRoot();
      expect(root, isNotNull);

      final topLevel = await root!.getKidElements();
      expect(topLevel, hasLength(1),
          reason: 'A tagged document has a single top-level element '
              '(ISO 32000-1, 14.8.4.2).');
      final documentElement = topLevel.single;
      expect((await documentElement.getRole())?.getValue(),
          equals(StandardRoles.document));

      final kids = await documentElement.getKids();
      final roles = <String?>[];
      for (final kid in kids) {
        roles.add((await kid.getRole())?.getValue());
      }
      expect(roles, equals([StandardRoles.h1, StandardRoles.p]));

      final heading = kids.first as PdfStructElem;
      expect((await heading.getTitle())?.getValue(), equals('Chapter 1'));
      expect((await heading.getLang())?.getValue(), equals('en-GB'));

      final paragraph = kids[1] as PdfStructElem;
      expect((await paragraph.getAlt())?.getValue(), equals('A paragraph'));
      expect((await paragraph.getActualText())?.getValue(), equals('body'));
      expect((await paragraph.getE())?.getValue(), equals('expanded'));

      // The marked-content identifiers of both elements resolve back to them
      // through the parent tree (14.7.4.4).
      final page = (await document.pageAt(1))!;
      final structParents = await page.getStructParents();
      expect(structParents, isNotNull);

      final entry = await root.getParentTreeEntry(structParents!);
      expect(entry, isA<PdfArray>());
      final array = entry as PdfArray;
      expect(array.size(), equals(2));

      final ownerOfMcid0 = await array.dictionaryEntry(0);
      final ownerOfMcid1 = await array.dictionaryEntry(1);
      expect((await PdfStructElem(ownerOfMcid0!).getRole())?.getValue(),
          equals(StandardRoles.h1));
      expect((await PdfStructElem(ownerOfMcid1!).getRole())?.getValue(),
          equals(StandardRoles.p));

      // /ParentTreeNextKey must be greater than any key in use.
      final nextKey = await root.getParentTreeNextKey();
      expect(nextKey, greaterThan(structParents));

      // The page content really carries the identifiers.
      final content = String.fromCharCodes(await page.contentPayload());
      expect(content, contains('BDC'));
      expect(content, contains('EMC'));

      await document.close();
    });

    test('The marked-content reference kept by the element matches its MCID',
        () async {
      final builder = BytesBuilder();
      final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      document.enableTagging();
      final page = await document.appendBlankPage();

      final pointer = await TagTreePointer.create(document);
      pointer.setPageForTagging(page);
      await pointer.addTag(StandardRoles.p);
      final first = await pointer.addMarkedContentReference();
      final second = await pointer.addMarkedContentReference();

      expect(await first.getMcid(), equals(0));
      expect(await second.getMcid(), equals(1));
      expect(first, isA<PdfMcrNumber>(),
          reason: 'A sequence on the element page uses the compact integer '
              'form (14.7.4.2).');

      final kids = await pointer.getCurrentStructElem().getKids();
      expect(kids, hasLength(2));
      expect(kids.every((kid) => kid is PdfMcr), isTrue);

      await document.close();
    });

    test('Object references give an annotation a StructParent', () async {
      final builder = BytesBuilder();
      final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      document.enableTagging();
      final page = await document.appendBlankPage();

      final annotation = PdfDictionary();
      annotation.put(PdfName.type, PdfName('Annot'));
      annotation.put(PdfName.subtype, PdfName('Link'));
      annotation.put(PdfName('Rect'), PdfArray.fromInts([0, 0, 10, 10]));
      annotation.attachToDocument(document);
      final annots = PdfArray();
      annots.add(annotation);
      page.pdfRepresentation().put(PdfName.annots, annots);

      final pointer = await TagTreePointer.create(document);
      pointer.setPageForTagging(page);
      await pointer.addTag(StandardRoles.link);
      final objRef = await pointer.addObjectReference(annotation);

      expect(await objRef.getReferencedObject(), same(annotation));
      final structParent =
          (await annotation.numberEntry(PdfName.structParent))?.intValue();
      expect(structParent, isNotNull);

      final root = document.structureRoot();
      final owner = await root.getParentTreeEntry(structParent!);
      expect(owner, isA<PdfDictionary>());
      expect(
          (await PdfStructElem(owner as PdfDictionary).getRole())?.getValue(),
          equals(StandardRoles.link));

      final kids = await pointer.getCurrentStructElem().getKids();
      expect(kids.single, isA<PdfObjRef>());

      await document.close();
    });

    test('Element identifiers are recorded in the IDTree', () async {
      final builder = BytesBuilder();
      final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      document.enableTagging();
      await document.appendBlankPage();

      final pointer = await TagTreePointer.create(document);
      await pointer.addTag(StandardRoles.table);
      await pointer.setStructureElementId('table-1');
      final table = pointer.getCurrentStructElem();

      final root = document.structureRoot();
      final resolved = await root.getElementById(PdfString('table-1'));
      expect(resolved, isNotNull);
      expect(resolved!.pdfRepresentation(), same(table.pdfRepresentation()));

      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(builder.toBytes()));
      final reopenedRoot = await reopened.loadStructureRoot();
      final ids = await reopenedRoot!.getElementIds();
      expect(ids.keys, contains('table-1'));
      final again = await reopenedRoot.getElementById(PdfString('table-1'));
      expect((await again!.getRole())?.getValue(), equals(StandardRoles.table));
      await reopened.close();
    });

    test('Removing an element identifier clears the IDTree entry', () async {
      final builder = BytesBuilder();
      final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      document.enableTagging();
      await document.appendBlankPage();

      final pointer = await TagTreePointer.create(document);
      await pointer.addTag(StandardRoles.p);
      await pointer.setStructureElementId('p-1');
      final element = pointer.getCurrentStructElem();
      await element.removeStructureElementId();

      final root = document.structureRoot();
      expect(await root.getElementById(PdfString('p-1')), isNull);
      expect(root.pdfRepresentation().containsKey(PdfName.idTree), isFalse);

      await document.close();
    });
  });

  group('Structure attributes', () {
    test('A single attribute object is stored directly in /A', () async {
      final builder = BytesBuilder();
      final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      document.enableTagging();
      await document.appendBlankPage();

      final pointer = await TagTreePointer.create(document);
      await pointer.addTag(StandardRoles.l);
      final attributes = PdfStructureAttributes.list()
        ..setListNumbering('Decimal');
      await pointer.addAttribute(attributes.pdfRepresentation());

      final element = pointer.getCurrentStructElem();
      final stored = await element.getAttributes();
      expect(stored, same(attributes.pdfRepresentation()));
      expect(await attributes.getOwner(), equals(StandardAttributeOwners.list));
      expect(await element.getAttributesList(), hasLength(1));
      expect(await element.getAttributeRevision(attributes.pdfRepresentation()),
          equals(0));

      await document.close();
    });

    test('A revision number turns /A into an array of pairs', () async {
      final builder = BytesBuilder();
      final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      document.enableTagging();
      await document.appendBlankPage();

      final pointer = await TagTreePointer.create(document);
      await pointer.addTag(StandardRoles.td);
      final element = pointer.getCurrentStructElem();

      final layout = PdfStructureAttributes.layout()..setTextAlign('Center');
      final table = PdfStructureAttributes.table()
        ..setRowSpan(2)
        ..setColSpan(3)
        ..setScope('Row');

      await element.addAttribute(layout.pdfRepresentation());
      await element.addAttribute(table.pdfRepresentation(), revision: 4);

      final raw = await element.getAttributes();
      expect(raw, isA<PdfArray>());
      final array = raw as PdfArray;
      // The object, then the object and its revision number (14.7.5.3).
      expect(array.size(), equals(3));
      expect(await array.get(2), isA<PdfNumber>());

      expect(await element.getAttributesList(), hasLength(2));
      expect(await element.getAttributeRevision(table.pdfRepresentation()),
          equals(4));
      expect(await element.getAttributeRevision(layout.pdfRepresentation()),
          equals(0));

      expect(await element.removeAttribute(table.pdfRepresentation()), isTrue);
      expect(await element.getAttributesList(), hasLength(1));
      expect((await element.getAttributes() as PdfArray).size(), equals(1));

      await document.close();
    });

    test('Attribute classes resolve through the ClassMap', () async {
      final builder = BytesBuilder();
      final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      document.enableTagging();
      await document.appendBlankPage();

      final shared = PdfStructureAttributes.layout()
        ..setPlacement('Block')
        ..setTextIndent(12);

      final pointer = await TagTreePointer.create(document);
      await pointer.addTag(StandardRoles.p);
      await pointer.addAttributeClass('Indented',
          attributes: shared.pdfRepresentation());

      final element = pointer.getCurrentStructElem();
      expect(
          await element.getAttributeClasses(), equals([PdfName('Indented')]));

      final root = document.structureRoot();
      expect(await root.getAttributeClass(PdfName('Indented')),
          same(shared.pdfRepresentation()));

      await element.addAttributeClass(PdfName('Emphasised'), revision: 2);
      expect(await element.getAttributeClassRevision(PdfName('Emphasised')),
          equals(2));
      expect(await element.getAttributeClasses(), hasLength(2));

      await document.close();
    });

    test('Attribute values are checked against the specification', () {
      final attributes = PdfStructureAttributes.table();
      expect(() => attributes.setScope('Diagonal'), throwsArgumentError);
      expect(() => attributes.setRowSpan(0), throwsArgumentError);
      expect(() => PdfStructureAttributes.list().setListNumbering('Roman'),
          throwsArgumentError);
      expect(() => PdfStructureAttributes.printField().setChecked('maybe'),
          throwsArgumentError);
      expect(() => PdfStructureAttributes.layout().setColor([2, 0, 0]),
          throwsArgumentError);
      expect(() => PdfStructureAttributes.layout().setBBox([0, 0, 1]),
          throwsArgumentError);
    });

    test('Revision numbers of a structure element start at zero', () async {
      final builder = BytesBuilder();
      final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      document.enableTagging();
      await document.appendBlankPage();

      final pointer = await TagTreePointer.create(document);
      await pointer.addTag(StandardRoles.p);
      final element = pointer.getCurrentStructElem();

      expect(await element.getRevision(), equals(0));
      expect(element.pdfRepresentation().containsKey(PdfName.r), isFalse);
      expect(await element.incrementRevision(), equals(1));
      expect(await element.getRevision(), equals(1));
      expect(element.pdfRepresentation().containsKey(PdfName.r), isTrue);
      expect(() => element.setRevision(-1), throwsArgumentError);

      await document.close();
    });

    test('Accessibility properties are written onto the element', () async {
      final builder = BytesBuilder();
      final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      document.enableTagging();
      await document.appendBlankPage();

      final pointer = await TagTreePointer.create(document);
      await pointer.addTag(StandardRoles.figure);
      final element = pointer.getCurrentStructElem();

      final properties = AccessibilityProperties()
        ..setRole(StandardRoles.figure)
        ..setAlternateDescription('A bar chart of quarterly revenue')
        ..setLanguage('en-US')
        ..setTitle('Revenue')
        ..setStructureElementId('figure-1')
        ..addAttributes(
            PdfStructureAttributes.layout()..setBBox([0, 0, 100, 50]));
      await properties.applyTo(element);

      expect((await element.getAlt())?.getValue(),
          equals('A bar chart of quarterly revenue'));
      expect((await element.getLang())?.getValue(), equals('en-US'));
      expect((await element.getTitle())?.getValue(), equals('Revenue'));
      expect((await element.getStructureElementId())?.getValue(),
          equals('figure-1'));
      expect(await element.getAttributesList(), hasLength(1));

      await document.close();
    });
  });
}

/// Writes a small tagged document with one heading and one paragraph, each
/// bracketed by a marked-content sequence on the page.
Future<Uint8List> _buildTaggedDocument() async {
  final builder = BytesBuilder();
  final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
  document.enableTagging();
  final page = await document.appendBlankPage();
  final canvas = await PdfCanvas.fromPage(page);

  final pointer = await TagTreePointer.create(document);
  pointer.setPageForTagging(page);

  await pointer.addTag(StandardRoles.h1);
  pointer
    ..setTitle('Chapter 1')
    ..setLang('en-GB');
  var mcr = await pointer.addMarkedContentReference();
  await canvas.beginMarkedContent(
      PdfName(StandardRoles.h1), await pointer.markedContentProperties(mcr));
  canvas.beginText().moveText(50, 700).showText('Chapter 1').endText();
  canvas.endMarkedContent();
  await pointer.moveToParent();

  await pointer.addTag(StandardRoles.p);
  pointer
    ..setAlt('A paragraph')
    ..setActualText('body')
    ..setExpansion('expanded');
  mcr = await pointer.addMarkedContentReference();
  await canvas.beginMarkedContent(
      PdfName(StandardRoles.p), await pointer.markedContentProperties(mcr));
  canvas.beginText().moveText(50, 680).showText('Body text').endText();
  canvas.endMarkedContent();

  await document.close();
  return builder.toBytes();
}
