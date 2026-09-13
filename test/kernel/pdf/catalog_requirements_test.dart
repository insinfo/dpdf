import 'dart:typed_data';

import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/viewer/pdf_requirement.dart';
import 'package:test/test.dart';

void main() {
  group('document requirements (ISO 32000-1:2008, 12.10, Tables 264 and 265)',
      () {
    test('the EnableJavaScripts requirement survives a roundtrip', () async {
      final bytes = BytesBuilder();
      final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await doc.appendBlankPage();
      await doc.rootCatalog().addRequirement(PdfRequirement.forJavaScripts());
      await doc.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);

      final requirements =
          await reopened.rootCatalog().getDocumentRequirements();
      expect(requirements, hasLength(1));
      final requirement = requirements.single;
      expect(await requirement.pdfRepresentation().nameEntry(PdfName.type),
          PdfRequirement.requirement);
      expect(await requirement.getRequirementType(),
          PdfRequirement.enableJavaScripts);
      expect(await requirement.getHandlers(), isEmpty);
      await requirement.validate();
    });

    test('a catalog without /Requirements reports none', () async {
      final bytes = BytesBuilder();
      final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await doc.appendBlankPage();
      await doc.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      expect(await reopened.rootCatalog().getRequirements(), isNull);
      expect(await reopened.rootCatalog().getDocumentRequirements(), isEmpty);
    });

    test('/RH is refused on the EnableJavaScripts requirement', () async {
      final requirement = PdfRequirement.forJavaScripts();
      final handler =
          PdfRequirementHandler.create(PdfRequirementHandlerType.javaScript);
      await handler.setScript('checkJavaScript');

      expect(
          () => requirement.addHandler(handler), throwsA(isA<PdfException>()));
      expect(
          requirement.pdfRepresentation().containsKey(PdfRequirement.handlers),
          isFalse);
    });

    test('a requirement of another type may list handlers', () async {
      final requirement =
          PdfRequirement.ofType(PdfName.intern('EnableSomethingElse'));
      final js =
          PdfRequirementHandler.create(PdfRequirementHandlerType.javaScript);
      await js.setScript('verifyIt');
      final noOp = PdfRequirementHandler.create(PdfRequirementHandlerType.noOp);
      await requirement.addHandler(js);
      await requirement.addHandler(noOp);

      final handlers = await requirement.getHandlers();
      expect(handlers, hasLength(2));
      expect(await handlers[0].pdfRepresentation().nameEntry(PdfName.type),
          PdfRequirementHandler.reqHandler);
      expect(await handlers[0].getHandlerType(),
          PdfRequirementHandlerType.javaScript);
      expect(await handlers[0].getScript(), 'verifyIt');
      expect(
          await handlers[1].getHandlerType(), PdfRequirementHandlerType.noOp);
      expect(await handlers[1].getScript(), isNull);
      await requirement.validate();
    });

    test('/Script is refused on a NoOp handler', () async {
      final handler =
          PdfRequirementHandler.create(PdfRequirementHandlerType.noOp);
      expect(() => handler.setScript('anything'), throwsA(isA<PdfException>()));
    });

    test('a requirement without /S is refused by the catalog', () async {
      final bytes = BytesBuilder();
      final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await doc.appendBlankPage();

      final broken = PdfRequirement(PdfDictionary());
      expect(broken.validate, throwsA(isA<PdfException>()));
      expect(() => doc.rootCatalog().addRequirement(broken),
          throwsA(isA<PdfException>()));
      expect(await doc.rootCatalog().getRequirements(), isNull);
      await doc.close();
    });

    test('an EnableJavaScripts requirement carrying /RH fails validation',
        () async {
      final requirement = PdfRequirement.forJavaScripts();
      // Force the entry past addHandler, the way a foreign writer might.
      final smuggled =
          PdfRequirement.ofType(PdfName.intern('EnableSomethingElse'));
      await smuggled.addHandler(
          PdfRequirementHandler.create(PdfRequirementHandlerType.noOp));
      requirement.pdfRepresentation().put(
          PdfRequirement.handlers,
          (await smuggled
              .pdfRepresentation()
              .arrayEntry(PdfRequirement.handlers))!);

      expect(requirement.validate, throwsA(isA<PdfException>()));
    });

    test('several requirements keep their order', () async {
      final bytes = BytesBuilder();
      final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await doc.appendBlankPage();
      await doc.rootCatalog().addRequirement(PdfRequirement.forJavaScripts());
      await doc
          .rootCatalog()
          .addRequirement(PdfRequirement.ofType(PdfName.intern('EnableX')));
      await doc.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final requirements =
          await reopened.rootCatalog().getDocumentRequirements();
      expect(requirements, hasLength(2));
      expect(await requirements[0].getRequirementType(),
          PdfRequirement.enableJavaScripts);
      expect(await requirements[1].getRequirementType(),
          PdfName.intern('EnableX'));
    });
  });
}
