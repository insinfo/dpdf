import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/tagging/pdf_namespace.dart';
import 'package:dpdf/src/kernel/pdf/tagging/standard_namespaces.dart';
import 'package:dpdf/src/kernel/pdf/tagging/standard_roles.dart';
import 'package:dpdf/src/kernel/pdf/tagging/tag_tree_pointer.dart';
import 'package:test/test.dart';

void main() {
  group('Role map', () {
    test('A chain of mappings resolves to the final role', () async {
      final document = _newTaggedDocument();
      final root = document.structureRoot();
      await root.addRoleMapping('Chapter', 'Section');
      await root.addRoleMapping('Section', StandardRoles.sect);

      expect(await root.resolveRole('Chapter'), equals(StandardRoles.sect));
      expect(await root.resolveRole(StandardRoles.p), equals(StandardRoles.p));

      await document.close();
    });

    test('A circular mapping terminates instead of looping', () async {
      final document = _newTaggedDocument();
      final root = document.structureRoot();
      // 14.7.3 NOTE 2 explicitly permits circular chains.
      await root.addRoleMapping('A', 'B');
      await root.addRoleMapping('B', 'A');

      expect(await root.resolveRole('A'), isIn(['A', 'B']));

      await document.close();
    });

    test('An unknown role is refused unless the role map explains it',
        () async {
      final document = _newTaggedDocument();
      final context = document.taggingContext()!;
      final pointer = await TagTreePointer.create(document);

      expect(context.forbidUnknownRoles, isTrue);
      await expectLater(pointer.addTag('Frobnicate'), throwsArgumentError);

      await document.structureRoot()
          .addRoleMapping('Frobnicate', StandardRoles.p);
      await pointer.addTag('Frobnicate');
      expect(await pointer.getRole(), equals('Frobnicate'));
      expect(await context.resolveRole('Frobnicate'),
          equals(StandardRoles.p));

      context.forbidUnknownRoles = false;
      await pointer.addTag('Whatever');
      expect(await pointer.getRole(), equals('Whatever'));

      await document.close();
    });
  });

  group('Standard structure types', () {
    test('Every category holds the types 14.8.4 lists', () {
      expect(StandardRoles.groupingTypes, contains(StandardRoles.document));
      expect(StandardRoles.groupingTypes, contains(StandardRoles.toci));
      expect(StandardRoles.blockLevelTypes, contains(StandardRoles.p));
      expect(StandardRoles.blockLevelTypes, contains(StandardRoles.tHead));
      expect(StandardRoles.listTypes,
          equals({StandardRoles.l, StandardRoles.li, StandardRoles.lbl,
            StandardRoles.lBody}));
      expect(StandardRoles.tableTypes, contains(StandardRoles.td));
      expect(StandardRoles.inlineLevelTypes, contains(StandardRoles.quote));
      expect(StandardRoles.inlineLevelTypes, contains(StandardRoles.warichu));
      expect(StandardRoles.illustrationTypes,
          equals({StandardRoles.figure, StandardRoles.formula,
            StandardRoles.form}));

      expect(StandardRoles.isStandardType(StandardRoles.bibEntry), isTrue);
      expect(StandardRoles.isStandardType('Frobnicate'), isFalse);
    });

    test('Headings are recognized by name', () {
      expect(StandardRoles.isHeading(StandardRoles.h), isTrue);
      expect(StandardRoles.isHeading('H1'), isTrue);
      expect(StandardRoles.isHeading('H12'), isTrue);
      expect(StandardRoles.isHeading('H0'), isFalse);
      expect(StandardRoles.isHeading('Header'), isFalse);
      expect(StandardRoles.isHeading(StandardRoles.p), isFalse);
    });

    test('A role belongs to the namespace that standardizes it', () {
      expect(
          StandardNamespaces.roleBelongsToStandardNamespace(
              StandardRoles.h1, StandardNamespaces.pdf17),
          isTrue);
      expect(
          StandardNamespaces.roleBelongsToStandardNamespace(
              StandardRoles.artifact, StandardNamespaces.pdf17),
          isFalse);
      expect(
          StandardNamespaces.roleBelongsToStandardNamespace(
              StandardRoles.artifact, StandardNamespaces.pdf20),
          isTrue);
      expect(
          StandardNamespaces.roleBelongsToStandardNamespace(
              'H7', StandardNamespaces.pdf20),
          isTrue);
    });
  });

  group('Namespaces', () {
    test('The default namespace is declared once and reused', () async {
      final builder = BytesBuilder();
      final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      document.enableTagging();
      await document.appendBlankPage();

      final first = await PdfNamespace.getDefault(document);
      final second = await PdfNamespace.getDefault(document);
      expect(await first.getNamespaceName(), equals(StandardNamespaces.pdf17));
      expect(first.pdfRepresentation(), same(second.pdfRepresentation()));

      final namespaces = await document.structureRoot().getNamespaces();
      expect(namespaces, hasLength(1));

      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(builder.toBytes()));
      final root = await reopened.loadStructureRoot();
      final reread = await root!.getNamespaces();
      expect(reread, hasLength(1));
      expect(await reread.single.getNamespaceName(),
          equals(StandardNamespaces.pdf17));
      await reopened.close();
    });

    test('A tag created under a namespace records it in /NS', () async {
      final builder = BytesBuilder();
      final document = PdfDocument(writer: PdfWriter.fromBytesBuilder(builder));
      document.enableTagging();
      await document.appendBlankPage();

      final context = document.taggingContext()!;
      final namespace = await context.useStandardNamespace();
      final pointer = await TagTreePointer.create(document);
      pointer.setNamespaceForNewTags(namespace);
      await pointer.addTag(StandardRoles.p);

      final element = pointer.getCurrentStructElem();
      final stored = await element.getNamespace();
      expect(stored, isNotNull);
      expect(await stored!.getNamespaceName(),
          equals(StandardNamespaces.pdf17));

      await document.close();
    });

    test('RoleMapNS maps a role to the default namespace', () async {
      final document = _newTaggedDocument();
      final namespace =
          await PdfNamespace.fetch(document, 'http://example.org/ns');
      await namespace.addNamespaceRoleMapping('Chapter', StandardRoles.h1);

      expect(await namespace.resolveNamespaceRole('Chapter'),
          equals(PdfName(StandardRoles.h1)));
      expect(await namespace.resolveNamespaceRoleTarget('Chapter'), isNull);
      expect(await namespace.resolveNamespaceRole('Unknown'), isNull);

      await document.close();
    });

    test('RoleMapNS can name the namespace it maps into', () async {
      final document = _newTaggedDocument();
      final source =
          await PdfNamespace.fetch(document, 'http://example.org/source');
      final target = await PdfNamespace.fetch(document, StandardNamespaces.pdf20);
      await source.addNamespaceRoleMappingWithTarget(
          'Chapter', StandardRoles.title, target);

      expect(await source.resolveNamespaceRole('Chapter'),
          equals(PdfName(StandardRoles.title)));
      final resolvedTarget =
          await source.resolveNamespaceRoleTarget('Chapter');
      expect(resolvedTarget, isNotNull);
      expect(await resolvedTarget!.getNamespaceName(),
          equals(StandardNamespaces.pdf20));

      // The context resolves through the namespace before the document map.
      final context = document.taggingContext()!;
      expect(await context.resolveRole('Chapter', source),
          equals(StandardRoles.title));

      await document.close();
    });
  });
}

PdfDocument _newTaggedDocument() {
  final document =
      PdfDocument(writer: PdfWriter.fromBytesBuilder(BytesBuilder()));
  document.enableTagging();
  return document;
}
