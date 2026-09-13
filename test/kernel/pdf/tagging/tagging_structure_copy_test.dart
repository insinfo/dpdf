import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/tagging/pdf_struct_elem.dart';
import 'package:dpdf/src/kernel/pdf/tagging/standard_roles.dart';
import 'package:dpdf/src/kernel/pdf/tagging/structure_tree_copier.dart';
import 'package:dpdf/src/kernel/pdf/tagging/tag_tree_pointer.dart';
import 'package:test/test.dart';

void main() {
  group('Structure tree copying between documents', () {
    test('Copying one page brings only its structure along', () async {
      final sourceBytes = await _buildTwoPageTaggedDocument();
      final source = await PdfDocument.open(PdfReader.fromBytes(sourceBytes));

      final builder = BytesBuilder();
      final destination =
          PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));

      final result = await StructureTreeCopier.copyPagesWithStructure(
          source, destination, [1]);

      expect(result.pages, hasLength(1));
      expect(result.structure.roots, hasLength(1));
      expect(result.structure.copiedMarkedContentReferences, equals(2));

      final root = destination.structureRoot();
      final topLevel = await root.getKidElements();
      expect(topLevel, hasLength(1));
      expect((await topLevel.single.getRole())?.getValue(),
          equals(StandardRoles.document));

      final kids = await topLevel.single.getKids();
      final roles = <String?>[];
      for (final kid in kids) {
        roles.add((await kid.getRole())?.getValue());
      }
      // Only the first page's heading and paragraph survive; the second
      // page's paragraph is left behind with its page.
      expect(roles, equals([StandardRoles.h1, StandardRoles.p]));

      // The role map of the source document travels with the structure.
      final roleMap = await root.getRoleMap();
      expect(await roleMap.nameEntry(PdfName('Title')),
          equals(PdfName(StandardRoles.h1)));

      await destination.close();
      await source.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(builder.toBytes()));
      final reopenedRoot = await reopened.loadStructureRoot();
      expect(reopenedRoot, isNotNull);

      final page = (await reopened.pageAt(1))!;
      final structParents = await page.getStructParents();
      expect(structParents, isNotNull,
          reason: 'The copied page needs a parent tree key of its own '
              '(ISO 32000-1, 14.7.4.4).');

      final entry = await reopenedRoot!.getParentTreeEntry(structParents!);
      expect(entry, isA<PdfArray>());
      final array = entry as PdfArray;
      expect(array.size(), equals(2));
      expect(
          (await PdfStructElem((await array.dictionaryEntry(0))!).getRole())
              ?.getValue(),
          equals(StandardRoles.h1));
      expect(
          (await PdfStructElem((await array.dictionaryEntry(1))!).getRole())
              ?.getValue(),
          equals(StandardRoles.p));

      // The copied content still carries the same marked-content identifiers.
      final content = String.fromCharCodes(await page.contentPayload());
      expect(content, contains('BDC'));

      await reopened.close();
    });

    test('Copying both pages reproduces the whole tree', () async {
      final sourceBytes = await _buildTwoPageTaggedDocument();
      final source = await PdfDocument.open(PdfReader.fromBytes(sourceBytes));

      final builder = BytesBuilder();
      final destination =
          PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));

      final result = await StructureTreeCopier.copyPagesWithStructure(
          source, destination, [1, 2]);

      expect(result.pages, hasLength(2));
      expect(result.structure.copiedElements, equals(4),
          reason: 'Document, H1, P and the second page P.');
      expect(result.structure.copiedMarkedContentReferences, equals(3));
      expect(result.structure.droppedContentItems, isZero);

      final root = destination.structureRoot();
      final kids = await (await root.getKidElements()).single.getKids();
      expect(kids, hasLength(3));

      // Each copied page has its own parent tree key.
      final firstKey = await result.pages[0].getStructParents();
      final secondKey = await result.pages[1].getStructParents();
      expect(firstKey, isNotNull);
      expect(secondKey, isNotNull);
      expect(firstKey, isNot(equals(secondKey)));

      await destination.close();
      await source.close();
    });

    test('An annotation keeps its object reference across the copy', () async {
      final sourceBytes = await _buildTaggedDocumentWithLink();
      final source = await PdfDocument.open(PdfReader.fromBytes(sourceBytes));

      final builder = BytesBuilder();
      final destination =
          PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));

      final result = await StructureTreeCopier.copyPagesWithStructure(
          source, destination, [1]);
      expect(result.structure.copiedObjectReferences, equals(1));

      final copiedPage = result.pages.single;
      final annots =
          await copiedPage.pdfRepresentation().arrayEntry(PdfName.annots);
      expect(annots, isNotNull);
      final annotation = await annots!.dictionaryEntry(0);
      final structParent =
          (await annotation!.numberEntry(PdfName.structParent))?.intValue();
      expect(structParent, isNotNull);

      final owner =
          await destination.structureRoot().getParentTreeEntry(structParent!);
      expect(owner, isA<PdfDictionary>());
      expect(
          (await PdfStructElem(owner as PdfDictionary).getRole())?.getValue(),
          equals(StandardRoles.link));

      await destination.close();
      await source.close();
    });

    test('Copying into the same document is refused', () async {
      final builder = BytesBuilder();
      final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      document.enableTagging();
      await document.appendBlankPage();
      expect(
          () => StructureTreeCopier.copyPagesWithStructure(
              document, document, [1]),
          throwsArgumentError);
      await document.close();
    });

    test('An untagged source leaves the destination untouched', () async {
      final builder = BytesBuilder();
      final plain = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      await plain.appendBlankPage();
      await plain.close();

      final source =
          await PdfDocument.open(PdfReader.fromBytes(builder.toBytes()));
      final target = BytesBuilder();
      final destination =
          PdfDocument(writer: PdfWriter.fromBytesBuilder(target));

      final result = await StructureTreeCopier.copyPagesWithStructure(
          source, destination, [1]);
      expect(result.pages, hasLength(1));
      expect(result.structure.copiedElements, isZero);
      expect(result.structure.roots, isEmpty);

      await destination.close();
      await source.close();
    });
  });
}

/// Two pages: the first holds a heading and a paragraph, the second a second
/// paragraph. A role map entry is added so the copy can be checked for it.
Future<Uint8List> _buildTwoPageTaggedDocument() async {
  final builder = BytesBuilder();
  final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
  document.enableTagging();
  await document.structureRoot().addRoleMapping('Title', StandardRoles.h1);

  final first = await document.appendBlankPage();
  final second = await document.appendBlankPage();

  final pointer = await TagTreePointer.create(document);

  await _tagText(pointer, first, StandardRoles.h1, 'Chapter 1');
  await pointer.moveToParent();
  await _tagText(pointer, first, StandardRoles.p, 'First page body');
  await pointer.moveToParent();
  await _tagText(pointer, second, StandardRoles.p, 'Second page body');

  await document.close();
  return builder.toBytes();
}

Future<Uint8List> _buildTaggedDocumentWithLink() async {
  final builder = BytesBuilder();
  final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
  document.enableTagging();
  final page = await document.appendBlankPage();

  final annotation = PdfDictionary();
  annotation.put(PdfName.type, PdfName('Annot'));
  annotation.put(PdfName.subtype, PdfName('Link'));
  annotation.put(PdfName('Rect'), PdfArray.fromInts([10, 10, 100, 30]));
  annotation.attachToDocument(document);
  final annots = PdfArray();
  annots.add(annotation);
  page.pdfRepresentation().put(PdfName.annots, annots);

  final pointer = await TagTreePointer.create(document);
  pointer.setPageForTagging(page);
  await pointer.addTag(StandardRoles.link);
  await pointer.addObjectReference(annotation);

  await document.close();
  return builder.toBytes();
}

Future<void> _tagText(
    TagTreePointer pointer, page, String role, String text) async {
  pointer.setPageForTagging(page);
  await pointer.addTag(role);
  final mcr = await pointer.addMarkedContentReference();
  final canvas = await PdfCanvas.fromPage(page);
  await canvas.beginMarkedContent(
      PdfName(role), await pointer.markedContentProperties(mcr));
  canvas.beginText().moveText(50, 700).showText(text).endText();
  canvas.endMarkedContent();
}
