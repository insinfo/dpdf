import 'dart:typed_data';

import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/article/pdf_article_thread.dart';
import 'package:dpdf/src/kernel/pdf/article/pdf_bead.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_page.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:test/test.dart';

/// A document under construction, kept together with the sink it writes to.
class Building {
  Building(this.doc, this.bytes);

  final PdfDocument doc;
  final BytesBuilder bytes;
}

Building newDocument() {
  final bytes = BytesBuilder();
  return Building(PdfDocument.create(PdfWriter.fromBytesBuilder(bytes)), bytes);
}

Future<PdfDocument> reopen(Building building) async {
  await building.doc.close();
  final reopened =
      await PdfDocument.open(PdfReader.fromBytes(building.bytes.toBytes()));
  addTearDown(reopened.close);
  return reopened;
}

Rectangle at(double y) => Rectangle(158, y, 160, 658);

void main() {
  group('article threads (ISO 32000-1:2008, 12.4.3, Tables 160 and 161)', () {
    test('a three bead thread over two pages survives a roundtrip', () async {
      final building = newDocument();
      final doc = building.doc;
      final pageOne = await doc.appendBlankPage();
      final pageTwo = await doc.appendBlankPage();

      final thread = PdfArticleThread.create(doc);
      final info = PdfDictionary();
      info.put(PdfName.title, PdfString('Man Bites Dog'));
      thread.setInfo(info);
      await thread.appendBead(pageOne, at(247));
      await thread.appendBead(pageOne, at(246));
      await thread.appendBead(pageTwo, at(254));
      await doc.rootCatalog().addArticleThread(thread);

      final reopened = await reopen(building);
      final threads = await reopened.rootCatalog().getArticleThreads();
      expect(threads, hasLength(1));

      final reloaded = threads.single;
      expect(await reloaded.pdfRepresentation().nameEntry(PdfName.type),
          PdfArticleThread.thread);
      expect(
          (await (await reloaded.getInfo())!.stringEntry(PdfName.title))
              ?.decodeMappingText(),
          'Man Bites Dog');

      final beads = await reloaded.getBeads();
      expect(beads, hasLength(3));
      for (final bead in beads) {
        expect(await bead.pdfRepresentation().nameEntry(PdfName.type),
            PdfBead.bead);
      }
      expect((await beads[0].getRectangle())!.y, 247);
      expect((await beads[1].getRectangle())!.y, 246);
      expect((await beads[2].getRectangle())!.y, 254);

      // The list is circular: the last bead points back at the first.
      expect((await beads[2].getNext())!.reference(), beads[0].reference());
      expect((await beads[0].getPrevious())!.reference(), beads[2].reference());
      await reloaded.validate();
    });

    test('every bead lists its page in /P and the page lists it in /B',
        () async {
      final building = newDocument();
      final doc = building.doc;
      final pageOne = await doc.appendBlankPage();
      final pageTwo = await doc.appendBlankPage();

      final thread = PdfArticleThread.create(doc);
      await thread.appendBead(pageOne, at(10));
      await thread.appendBead(pageTwo, at(20));
      await thread.appendBead(pageOne, at(30));
      await doc.rootCatalog().addArticleThread(thread);

      final reopened = await reopen(building);
      final reloadedOne = (await reopened.pageAt(1))!;
      final reloadedTwo = (await reopened.pageAt(2))!;

      final beadsOne = await reloadedOne.getBeads();
      final beadsTwo = await reloadedTwo.getBeads();
      expect(beadsOne, hasLength(2));
      expect(beadsTwo, hasLength(1));
      // /B is in drawing order, which is the order the beads were added.
      expect((await beadsOne[0].getRectangle())!.y, 10);
      expect((await beadsOne[1].getRectangle())!.y, 30);

      final pageOfFirst = await beadsOne[0].getPage();
      expect(pageOfFirst!.pdfRepresentation().indirectHandle(),
          reloadedOne.pdfRepresentation().indirectHandle());
      final pageOfSecond = await beadsTwo[0].getPage();
      expect(pageOfSecond!.pdfRepresentation().indirectHandle(),
          reloadedTwo.pdfRepresentation().indirectHandle());
    });

    test('a single bead thread is its own next and previous', () async {
      final building = newDocument();
      final doc = building.doc;
      final page = await doc.appendBlankPage();
      final thread = PdfArticleThread.create(doc);
      final bead = await thread.appendBead(page, at(100));
      await doc.rootCatalog().addArticleThread(thread);

      expect((await bead.getNext())!.reference(), bead.reference());
      expect((await bead.getPrevious())!.reference(), bead.reference());

      final reopened = await reopen(building);
      final reloaded =
          (await reopened.rootCatalog().getArticleThreads()).single;
      expect(await reloaded.getBeads(), hasLength(1));
      await reloaded.validate();
    });

    test('two threads live side by side in /Threads', () async {
      final building = newDocument();
      final doc = building.doc;
      final page = await doc.appendBlankPage();

      final first = PdfArticleThread.create(doc);
      await first.appendBead(page, at(1));
      await first.appendBead(page, at(2));
      final second = PdfArticleThread.create(doc);
      await second.appendBead(page, at(3));
      await doc.rootCatalog().addArticleThread(first);
      await doc.rootCatalog().addArticleThread(second);

      final reopened = await reopen(building);
      final threads = await reopened.rootCatalog().getArticleThreads();
      expect(threads, hasLength(2));
      expect(await threads[0].getBeads(), hasLength(2));
      expect(await threads[1].getBeads(), hasLength(1));
      // The page lists the beads of both threads.
      expect(await (await reopened.pageAt(1))!.getBeads(), hasLength(3));
    });

    test('a catalog without /Threads reports no articles', () async {
      final building = newDocument();
      await building.doc.appendBlankPage();
      final reopened = await reopen(building);

      expect(await reopened.rootCatalog().getThreads(), isNull);
      expect(await reopened.rootCatalog().getArticleThreads(), isEmpty);
      expect(await (await reopened.pageAt(1))!.getBeads(), isEmpty);
    });

    test('a thread without /F fails validation', () async {
      final building = newDocument();
      final thread = PdfArticleThread.create(building.doc);
      await building.doc.appendBlankPage();

      expect(await thread.getBeads(), isEmpty);
      expect(thread.validate, throwsA(isA<PdfException>()));
      expect(await thread.isValid(), isFalse);
      await building.doc.close();
    });

    test('a bead chain that loses its /N does not close the circle', () async {
      final building = newDocument();
      final doc = building.doc;
      final page = await doc.appendBlankPage();
      final thread = PdfArticleThread.create(doc);
      await thread.appendBead(page, at(1));
      await thread.appendBead(page, at(2));
      final last = await thread.appendBead(page, at(3));

      last.pdfRepresentation().remove(PdfBead.nextKey);
      expect(thread.getBeads, throwsA(isA<PdfException>()));
      expect(await thread.isValid(), isFalse);
      await doc.close();
    });

    test('a bead chain that folds back on itself is rejected', () async {
      final building = newDocument();
      final doc = building.doc;
      final page = await doc.appendBlankPage();
      final thread = PdfArticleThread.create(doc);
      await thread.appendBead(page, at(1));
      final second = await thread.appendBead(page, at(2));
      final last = await thread.appendBead(page, at(3));

      // The last bead points at the second instead of at the first, so the
      // walk never reaches the head again.
      last.pdfRepresentation().put(PdfBead.nextKey, second.reference());
      expect(thread.getBeads, throwsA(isA<PdfException>()));
      await doc.close();
    });

    test('a /V that disagrees with the /N chain is rejected', () async {
      final building = newDocument();
      final doc = building.doc;
      final page = await doc.appendBlankPage();
      final thread = PdfArticleThread.create(doc);
      await thread.appendBead(page, at(1));
      final second = await thread.appendBead(page, at(2));
      final last = await thread.appendBead(page, at(3));

      second.pdfRepresentation().put(PdfBead.previousKey, last.reference());
      expect(thread.getBeads, throwsA(isA<PdfException>()));
      await doc.close();
    });

    test('a closing link whose /V skips the last bead is rejected', () async {
      final building = newDocument();
      final doc = building.doc;
      final page = await doc.appendBlankPage();
      final thread = PdfArticleThread.create(doc);
      final first = await thread.appendBead(page, at(1));
      final second = await thread.appendBead(page, at(2));
      await thread.appendBead(page, at(3));

      first.pdfRepresentation().put(PdfBead.previousKey, second.reference());
      expect(thread.getBeads, throwsA(isA<PdfException>()));
      await doc.close();
    });

    test('validate demands /R, /P and /T on the beads', () async {
      final building = newDocument();
      final doc = building.doc;
      final page = await doc.appendBlankPage();

      final noRectangle = PdfArticleThread.create(doc);
      final bead = await noRectangle.appendBead(page, at(1));
      await noRectangle.appendBead(page, at(2));
      bead.pdfRepresentation().remove(PdfBead.rectangleKey);
      expect(noRectangle.validate, throwsA(isA<PdfException>()));

      final noPage = PdfArticleThread.create(doc);
      final other = await noPage.appendBead(page, at(3));
      other.pdfRepresentation().remove(PdfBead.pageKey);
      expect(noPage.validate, throwsA(isA<PdfException>()));

      final noThread = PdfArticleThread.create(doc);
      final headless = await noThread.appendBead(page, at(4));
      headless.pdfRepresentation().remove(PdfBead.threadKey);
      expect(noThread.validate, throwsA(isA<PdfException>()));

      await doc.close();
    });

    test('a bead whose /T names another thread is rejected', () async {
      final building = newDocument();
      final doc = building.doc;
      final page = await doc.appendBlankPage();

      final owner = PdfArticleThread.create(doc);
      final stranger = PdfArticleThread.create(doc);
      await owner.appendBead(page, at(1));
      final second = await owner.appendBead(page, at(2));
      second.pdfRepresentation().put(PdfBead.threadKey, stranger.reference());

      expect(owner.validate, throwsA(isA<PdfException>()));
      await doc.close();
    });

    test('a bead cannot point at a page that is not in the document', () async {
      final building = newDocument();
      final doc = building.doc;
      await doc.appendBlankPage();
      final thread = PdfArticleThread.create(doc);
      final detached = PdfPage(PdfDictionary());

      expect(() => thread.appendBead(detached, at(1)),
          throwsA(isA<PdfException>()));
      await doc.close();
    });

    test('a thread that is not in a document cannot take beads', () async {
      final building = newDocument();
      final page = await building.doc.appendBlankPage();
      final orphan = PdfArticleThread(PdfDictionary());

      expect(
          () => orphan.appendBead(page, at(1)), throwsA(isA<PdfException>()));
      expect(orphan.reference, throwsA(isA<PdfException>()));
      await building.doc.close();
    });
  });
}
