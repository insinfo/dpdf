import '../../exceptions/pdf_exception.dart';
import '../../geom/rectangle.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_page.dart';

/// A bead dictionary of ISO 32000-1:2008, 12.4.3, Table 161.
///
/// A bead is one content item of an article thread. Table 161 requires `/N`,
/// `/V`, `/P` and `/R`, and chains the beads of a thread into a circular
/// doubly linked list through `/N` (next) and `/V` (previous); `/T` names the
/// thread the bead belongs to and is required on the first bead.
///
/// Beads are created by [PdfArticleThread.appendBead], which maintains the
/// circular list; this class wraps an existing bead dictionary.
class PdfBead extends PdfObjectWrapper<PdfDictionary> {
  /// The `/Type` value of a bead dictionary.
  static final PdfName bead = PdfName.intern('Bead');

  /// `/T`, the thread this bead belongs to.
  static final PdfName threadKey = PdfName.intern('T');

  /// `/N`, the next bead in the thread.
  static final PdfName nextKey = PdfName.intern('N');

  /// `/V`, the previous bead in the thread.
  static final PdfName previousKey = PdfName.intern('V');

  /// `/P`, the page on which this bead appears.
  static final PdfName pageKey = PdfName.intern('P');

  /// `/R`, the location of this bead on the page.
  static final PdfName rectangleKey = PdfName.intern('R');

  /// Wraps an existing bead dictionary.
  PdfBead(super.pdfObject);

  /// Table 161 requires every bead reference to be indirect.
  @override
  bool requiresIndirectStorage() => true;

  /// The indirect reference of this bead, which Table 161 requires it to have.
  PdfIndirectReference reference() {
    final handle = pdfRepresentation().indirectHandle();
    if (handle == null) {
      throw PdfException(
          'A bead shall be an indirect object before it can be linked into a '
          'thread.');
    }
    return handle;
  }

  /// Sets `/R`, the rectangle locating this bead on its page.
  PdfBead setRectangle(Rectangle rectangle) {
    pdfRepresentation().put(rectangleKey, rectangle.toPdfArray());
    markChanged();
    return this;
  }

  /// Gets `/R`, or `null` when the required entry is missing.
  Future<Rectangle?> getRectangle() async {
    final array = await pdfRepresentation().arrayEntry(rectangleKey);
    return array == null ? null : await Rectangle.fromPdfArray(array);
  }

  /// Gets `/P`, the page this bead appears on, or `null` when absent.
  Future<PdfPage?> getPage() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(pageKey);
    return dictionary == null ? null : PdfPage(dictionary);
  }

  /// Gets `/N`, the next bead of the thread. In the last bead Table 161 makes
  /// this the first bead again.
  Future<PdfBead?> getNext() => _linked(nextKey);

  /// Gets `/V`, the previous bead of the thread. In the first bead Table 161
  /// makes this the last bead.
  Future<PdfBead?> getPrevious() => _linked(previousKey);

  /// Gets `/T`, the thread dictionary this bead belongs to, or `null`.
  Future<PdfDictionary?> getThreadDictionary() =>
      pdfRepresentation().dictionaryEntry(threadKey);

  Future<PdfBead?> _linked(PdfName key) async {
    final dictionary = await pdfRepresentation().dictionaryEntry(key);
    return dictionary == null ? null : PdfBead(dictionary);
  }
}
