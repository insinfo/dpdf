import 'dart:typed_data';

import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/viewer/pdf_viewer_preferences.dart';
import 'package:test/test.dart';

/// Builds a one page document, lets [build] touch its viewer preferences,
/// closes it and reopens the bytes, returning the reloaded preferences.
Future<PdfViewerPreferences?> roundtrip(
    Future<void> Function(PdfViewerPreferences) build) async {
  final bytes = BytesBuilder();
  final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
  await doc.appendBlankPage();
  final preferences = await doc.rootCatalog().viewerPreferences();
  await build(preferences);
  await doc.close();

  final reopened = await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
  addTearDown(reopened.close);
  return await reopened.rootCatalog().getViewerPreferences();
}

void main() {
  group('viewer preferences (ISO 32000-1:2008, 12.2, Table 150)', () {
    test('every boolean flag survives a roundtrip', () async {
      final reloaded = await roundtrip((prefs) async {
        prefs
            .setHideToolbar(true)
            .setHideMenubar(true)
            .setHideWindowUI(true)
            .setFitWindow(true)
            .setCenterWindow(true)
            .setDisplayDocTitle(true)
            .setPickTrayByPDFSize(true);
      });

      expect(reloaded, isNotNull);
      expect(await reloaded!.getHideToolbar(), isTrue);
      expect(await reloaded.getHideMenubar(), isTrue);
      expect(await reloaded.getHideWindowUI(), isTrue);
      expect(await reloaded.getFitWindow(), isTrue);
      expect(await reloaded.getCenterWindow(), isTrue);
      expect(await reloaded.getDisplayDocTitle(), isTrue);
      expect(await reloaded.getPickTrayByPDFSize(), isTrue);
    });

    test('absent flags fall back to the Table 150 default of false', () async {
      final reloaded = await roundtrip((prefs) async {
        prefs.setFitWindow(false);
      });

      expect(await reloaded!.getHideToolbar(), isFalse);
      expect(await reloaded.getHideMenubar(), isFalse);
      expect(await reloaded.getHideWindowUI(), isFalse);
      expect(await reloaded.getFitWindow(), isFalse);
      expect(await reloaded.getCenterWindow(), isFalse);
      expect(await reloaded.getDisplayDocTitle(), isFalse);
      // Table 150 leaves PickTrayByPDFSize to the reader, hence no default.
      expect(await reloaded.getPickTrayByPDFSize(), isNull);
    });

    test('name valued entries survive a roundtrip', () async {
      final reloaded = await roundtrip((prefs) async {
        prefs
            .setNonFullScreenPageMode(PdfNonFullScreenPageMode.useOutlines)
            .setDirection(PdfReadingDirection.r2l)
            .setViewArea(PdfPageBoundary.mediaBox)
            .setViewClip(PdfPageBoundary.bleedBox)
            .setPrintArea(PdfPageBoundary.trimBox)
            .setPrintClip(PdfPageBoundary.artBox)
            .setPrintScaling(PdfPrintScaling.none)
            .setDuplex(PdfDuplex.duplexFlipLongEdge);
      });

      expect(await reloaded!.getNonFullScreenPageMode(),
          PdfNonFullScreenPageMode.useOutlines);
      expect(await reloaded.getDirection(), PdfReadingDirection.r2l);
      expect(await reloaded.getViewArea(), PdfPageBoundary.mediaBox);
      expect(await reloaded.getViewClip(), PdfPageBoundary.bleedBox);
      expect(await reloaded.getPrintArea(), PdfPageBoundary.trimBox);
      expect(await reloaded.getPrintClip(), PdfPageBoundary.artBox);
      expect(await reloaded.getPrintScaling(), PdfPrintScaling.none);
      expect(await reloaded.getDuplex(), PdfDuplex.duplexFlipLongEdge);
    });

    test('name valued entries fall back to the Table 150 defaults', () async {
      final reloaded = await roundtrip((prefs) async {
        prefs.setFitWindow(true);
      });

      expect(await reloaded!.getNonFullScreenPageMode(),
          PdfNonFullScreenPageMode.useNone);
      expect(await reloaded.getDirection(), PdfReadingDirection.l2r);
      expect(await reloaded.getViewArea(), PdfPageBoundary.cropBox);
      expect(await reloaded.getViewClip(), PdfPageBoundary.cropBox);
      expect(await reloaded.getPrintArea(), PdfPageBoundary.cropBox);
      expect(await reloaded.getPrintClip(), PdfPageBoundary.cropBox);
      expect(await reloaded.getPrintScaling(), PdfPrintScaling.appDefault);
      // Table 150 gives no default for Duplex.
      expect(await reloaded.getDuplex(), isNull);
    });

    test('an unrecognized PrintScaling reads back as AppDefault', () async {
      final reloaded = await roundtrip((prefs) async {
        prefs.put(PdfViewerPreferences.printScaling, PdfName.intern('Bogus'));
      });

      expect(await reloaded!.getPrintScaling(), PdfPrintScaling.appDefault);
    });

    test('PrintPageRange and NumCopies survive a roundtrip', () async {
      final reloaded = await roundtrip((prefs) async {
        prefs
          ..setPrintPageRange([1, 3, 7, 7])
          ..setNumCopies(4);
      });

      expect(await reloaded!.getPrintPageRange(), [1, 3, 7, 7]);
      expect(await reloaded.getNumCopies(), 4);
    });

    test('a PrintPageRange with an odd number of integers is rejected', () {
      final prefs = PdfViewerPreferences();
      expect(() => prefs.setPrintPageRange([1, 3, 5]),
          throwsA(isA<PdfException>()));
      expect(() => prefs.setPrintPageRange([]), throwsA(isA<PdfException>()));
    });

    test('a PrintPageRange page number below one is rejected', () {
      final prefs = PdfViewerPreferences();
      expect(
          () => prefs.setPrintPageRange([0, 3]), throwsA(isA<PdfException>()));
    });

    test('a PrintPageRange sub-range that ends before it starts is rejected',
        () {
      final prefs = PdfViewerPreferences();
      expect(
          () => prefs.setPrintPageRange([9, 4]), throwsA(isA<PdfException>()));
    });

    test('NumCopies below one is rejected', () {
      final prefs = PdfViewerPreferences();
      expect(() => prefs.setNumCopies(0), throwsA(isA<PdfException>()));
      expect(() => prefs.setNumCopies(-2), throwsA(isA<PdfException>()));
    });

    test('a catalog without ViewerPreferences reports none', () async {
      final bytes = BytesBuilder();
      final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await doc.appendBlankPage();
      await doc.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      expect(await reopened.rootCatalog().getViewerPreferences(), isNull);
    });

    test('removing an entry restores its default', () async {
      final reloaded = await roundtrip((prefs) async {
        prefs.setDirection(PdfReadingDirection.r2l);
        prefs.remove(PdfViewerPreferences.direction);
      });

      expect(await reloaded!.getDirection(), PdfReadingDirection.l2r);
    });

    test('the legacy setDisplayDocTitle shortcut reuses the same dictionary',
        () async {
      final bytes = BytesBuilder();
      final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await doc.appendBlankPage();
      final prefs = await doc.rootCatalog().viewerPreferences();
      prefs.setFitWindow(true);
      doc.rootCatalog().setDisplayDocTitle(true);
      await doc.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final reloaded = await reopened.rootCatalog().getViewerPreferences();
      expect(await reloaded!.getFitWindow(), isTrue);
      expect(await reloaded.getDisplayDocTitle(), isTrue);
    });
  });
}
