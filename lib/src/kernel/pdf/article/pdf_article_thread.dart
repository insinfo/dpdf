import '../../exceptions/pdf_exception.dart';
import '../../geom/rectangle.dart';
import '../pdf_dictionary.dart';
import '../pdf_document.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_page.dart';
import 'pdf_bead.dart';

/// A thread dictionary of ISO 32000-1:2008, 12.4.3, Table 160.
///
/// An article thread defines the sequential flow of an article whose content
/// items are physically discontiguous. `/F` refers to the first bead, and the
/// beads are chained into a circular doubly linked list through their `/N` and
/// `/V` entries (Table 161). The optional `/I` entry holds a thread
/// information dictionary whose contents follow the syntax of the document
/// information dictionary (14.3.3).
class PdfArticleThread extends PdfObjectWrapper<PdfDictionary> {
  /// The `/Type` value of a thread dictionary, and the catalog key `/Threads`
  /// holds an array of them.
  static final PdfName thread = PdfName.intern('Thread');

  /// `/F`, the first bead of the thread.
  static final PdfName firstKey = PdfName.intern('F');

  /// `/I`, the thread information dictionary.
  static final PdfName infoKey = PdfName.intern('I');

  /// Wraps an existing thread dictionary.
  PdfArticleThread(super.pdfObject);

  /// Creates an empty thread, attached to [document] so that Table 160 can
  /// refer to it indirectly.
  PdfArticleThread.create(PdfDocument document) : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, thread);
    pdfRepresentation().attachToDocument(document);
  }

  /// Table 28 refers to threads indirectly.
  @override
  bool requiresIndirectStorage() => true;

  /// The indirect reference of this thread.
  PdfIndirectReference reference() {
    final handle = pdfRepresentation().indirectHandle();
    if (handle == null) {
      throw PdfException(
          'A thread shall be an indirect object before beads can point at it.');
    }
    return handle;
  }

  /// Sets `/I`, the thread information dictionary (title, author, creation
  /// date, in the syntax of the document information dictionary).
  PdfArticleThread setInfo(PdfDictionary info) {
    pdfRepresentation().put(infoKey, info);
    markChanged();
    return this;
  }

  /// Gets `/I`, or `null` when the thread carries no information dictionary.
  Future<PdfDictionary?> getInfo() =>
      pdfRepresentation().dictionaryEntry(infoKey);

  /// Gets `/F`, the first bead, or `null` when the thread is still empty.
  /// Table 160 makes `/F` required, so a thread without it is incomplete.
  Future<PdfBead?> getFirstBead() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(firstKey);
    return dictionary == null ? null : PdfBead(dictionary);
  }

  /// Appends a bead covering [rectangle] on [page] to the end of the thread,
  /// keeping the `/N` and `/V` chain circular and registering the bead in the
  /// page's `/B` array, as 12.4.3 requires.
  Future<PdfBead> appendBead(PdfPage page, Rectangle rectangle) async {
    final document = pdfRepresentation().indirectHandle()?.getDocument();
    if (document == null) {
      throw PdfException(
          'A thread shall belong to a document before beads are added to it.');
    }
    final pageReference = page.pdfRepresentation().indirectHandle();
    if (pageReference == null) {
      throw PdfException(
          'Table 161 requires /P to be an indirect reference to a page '
          'object, so the page shall be added to the document first.');
    }

    final dictionary = PdfDictionary();
    dictionary.put(PdfName.type, PdfBead.bead);
    dictionary.attachToDocument(document);
    final bead = PdfBead(dictionary);
    bead.setRectangle(rectangle);
    dictionary.put(PdfBead.pageKey, pageReference);
    dictionary.put(PdfBead.threadKey, reference());

    final first = await getFirstBead();
    if (first == null) {
      // A one bead thread is its own next and previous.
      dictionary.put(PdfBead.nextKey, bead.reference());
      dictionary.put(PdfBead.previousKey, bead.reference());
      pdfRepresentation().put(firstKey, bead.reference());
      markChanged();
    } else {
      final last = await first.getPrevious();
      if (last == null) {
        throw PdfException(
            'The first bead of the thread has no /V entry, so the circular '
            'list of 12.4.3 is already broken.');
      }
      last.pdfRepresentation().put(PdfBead.nextKey, bead.reference());
      last.markChanged();
      dictionary.put(PdfBead.previousKey, last.reference());
      dictionary.put(PdfBead.nextKey, first.reference());
      first.pdfRepresentation().put(PdfBead.previousKey, bead.reference());
      first.markChanged();
    }

    await page.addBead(bead);
    return bead;
  }

  /// Walks the thread from `/F` through `/N` and returns its beads in order.
  ///
  /// 12.4.3 chains the beads into a circular doubly linked list, so the walk
  /// shall come back to the first bead after visiting each bead once. A chain
  /// that breaks, that does not close, or whose `/V` entries disagree with its
  /// `/N` entries raises a [PdfException].
  Future<List<PdfBead>> getBeads() async {
    final first = await getFirstBead();
    if (first == null) return const [];

    final beads = <PdfBead>[first];
    final seen = <PdfIndirectReference>{first.reference()};
    var current = first;

    while (true) {
      final next = await current.getNext();
      if (next == null) {
        throw PdfException(
            'Bead ${current.reference()} has no /N entry, so the thread is '
            'not the circular list 12.4.3 requires.');
      }
      if (next.reference() == first.reference()) {
        await _checkBackLink(first, current);
        return beads;
      }
      if (!seen.add(next.reference())) {
        throw PdfException(
            'Bead ${next.reference()} is reached twice without passing '
            'through the first bead, so the thread does not close on itself.');
      }
      await _checkBackLink(next, current);
      beads.add(next);
      current = next;
    }
  }

  Future<void> _checkBackLink(PdfBead next, PdfBead current) async {
    final back = await next.getPrevious();
    if (back == null || back.reference() != current.reference()) {
      throw PdfException(
          'Bead ${next.reference()} has /V ${back?.reference()} but follows '
          '${current.reference()}, so /N and /V disagree.');
    }
  }

  /// Checks the thread against Tables 160 and 161: `/F` shall be present, the
  /// bead chain shall close on itself, every bead shall carry `/P` and `/R`,
  /// and any `/T` entry shall name this thread. The first bead is required to
  /// carry `/T`. Raises a [PdfException] describing the first problem found.
  Future<void> validate() async {
    final first = await getFirstBead();
    if (first == null) {
      throw PdfException(
          'Table 160 requires /F, the first bead of the thread.');
    }
    final beads = await getBeads();

    final firstThread = await first.getThreadDictionary();
    if (firstThread == null) {
      throw PdfException(
          'Table 161 requires /T on the first bead of a thread.');
    }

    final own = reference();
    for (final bead in beads) {
      if (await bead.getRectangle() == null) {
        throw PdfException(
            'Table 161 requires /R on bead ${bead.reference()}.');
      }
      if (await bead.getPage() == null) {
        throw PdfException(
            'Table 161 requires /P on bead ${bead.reference()}.');
      }
      final owner = await bead.getThreadDictionary();
      if (owner != null && owner.indirectHandle() != own) {
        throw PdfException(
            'Bead ${bead.reference()} has /T ${owner.indirectHandle()} but '
            'belongs to thread $own.');
      }
    }
  }

  /// Whether the thread is a well formed circular list, without raising.
  Future<bool> isValid() async {
    try {
      await validate();
      return true;
    } on PdfException {
      return false;
    }
  }
}
