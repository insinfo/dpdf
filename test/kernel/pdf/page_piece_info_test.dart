import 'dart:typed_data';

import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/viewer/pdf_page_piece.dart';
import 'package:test/test.dart';

void main() {
  group('page-piece dictionaries (ISO 32000-1:2008, 14.5, Tables 318 and 319)',
      () {
    final moment = DateTime(2024, 3, 17, 9, 41, 5);

    test('private data on a page and on the catalog survives a roundtrip',
        () async {
      final bytes = BytesBuilder();
      final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await doc.appendBlankPage();

      final pagePrivate = PdfDictionary();
      pagePrivate.put(PdfName.intern('Layer'), PdfNumber.fromInt(4));
      (await page.pieceInfo()).setData('PictureEdit',
          PdfApplicationData.modifiedAt(moment)..setPrivate(pagePrivate));

      (await doc.rootCatalog().pieceInfo()).setData(
          'AcmeAuthoring',
          PdfApplicationData.modifiedAt(moment)
            ..setPrivate(PdfString('project-42')));
      await doc.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);

      final reloadedPage = (await reopened.pageAt(1))!;
      final pagePiece = await reloadedPage.getPieceInfo();
      expect(pagePiece, isNotNull);
      expect(pagePiece!.producers(), contains('PictureEdit'));
      final pageData = (await pagePiece.getData('PictureEdit'))!;
      expect(
          (await pageData.getLastModified())!.isAtSameMomentAs(moment), isTrue);
      final restoredPrivate = await pageData.getPrivate();
      expect(restoredPrivate, isA<PdfDictionary>());
      expect(
          (await (restoredPrivate as PdfDictionary)
                  .numberEntry(PdfName.intern('Layer')))!
              .intValue(),
          4);

      final docPiece = await reopened.rootCatalog().getPieceInfo();
      final docData = (await docPiece!.getData('AcmeAuthoring'))!;
      expect(
          (await docData.getLastModified())!.isAtSameMomentAs(moment), isTrue);
      expect((await docData.getPrivate() as PdfString).decodeMappingText(),
          'project-42');
    });

    test('several products can keep data side by side', () async {
      final piece = PdfPagePiece();
      piece
          .setData('PictureEdit', PdfApplicationData.modifiedAt(moment))
          .setData(
              'PictureEditExtended', PdfApplicationData.modifiedAt(moment));

      expect(piece.producers(),
          containsAll(['PictureEdit', 'PictureEditExtended']));
      // 14.5 lets two data dictionaries share a modification date.
      expect(
          await (await piece.getData('PictureEdit'))!.getLastModified(),
          await (await piece.getData('PictureEditExtended'))!
              .getLastModified());
    });

    test('a data dictionary without /LastModified is rejected', () {
      final piece = PdfPagePiece();
      expect(() => piece.setData('PictureEdit', PdfApplicationData()),
          throwsA(isA<PdfException>()));
      expect(piece.producers(), isEmpty);
    });

    test('an empty product name is rejected', () {
      final piece = PdfPagePiece();
      expect(() => piece.setData('', PdfApplicationData.modifiedAt(moment)),
          throwsA(isA<PdfException>()));
    });

    test('/Private is optional', () async {
      final piece =
          PdfPagePiece().setData('Acme', PdfApplicationData.modifiedAt(moment));
      expect(await (await piece.getData('Acme'))!.getPrivate(), isNull);
    });

    test('a malformed /LastModified is reported', () {
      final data = PdfApplicationData();
      data
          .pdfRepresentation()
          .put(PdfApplicationData.lastModified, PdfString('not a date'));
      expect(data.getLastModified, throwsA(isA<PdfException>()));
    });

    test('removeData drops one product without touching the others', () async {
      final piece = PdfPagePiece()
          .setData('Acme', PdfApplicationData.modifiedAt(moment))
          .setData('Other', PdfApplicationData.modifiedAt(moment));

      piece.removeData('Acme');
      expect(await piece.getData('Acme'), isNull);
      expect(await piece.getData('Other'), isNotNull);
    });

    test('a page and a catalog without /PieceInfo report none', () async {
      final bytes = BytesBuilder();
      final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await doc.appendBlankPage();
      await doc.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      expect(await (await reopened.pageAt(1))!.getPieceInfo(), isNull);
      expect(await reopened.rootCatalog().getPieceInfo(), isNull);
    });
  });
}
