import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/filespec/pdf_file_spec.dart';
import 'pdf_action.dart';

/// Thread action, jumping to a bead on an article thread.
///
/// See ISO 32000-1:2008, 12.6.4.6, Table 205.
class PdfActionThread extends PdfAction {
  PdfActionThread(super.pdfObject);

  /// Creates a `/Thread` action targeting the thread at [index] of the
  /// document catalog's `/Threads` array (zero based).
  PdfActionThread.byIndex(int index) : super.ofType(PdfName.thread) {
    pdfRepresentation().put(PdfName.d, PdfNumber.fromInt(index));
  }

  /// Creates a `/Thread` action targeting the thread whose information
  /// dictionary carries [title].
  PdfActionThread.byTitle(String title) : super.ofType(PdfName.thread) {
    pdfRepresentation().put(PdfName.d, PdfString(title));
  }

  /// Creates a `/Thread` action targeting [thread] directly.
  PdfActionThread.byDictionary(PdfDictionary thread)
      : super.ofType(PdfName.thread) {
    pdfRepresentation().put(PdfName.d, thread);
  }

  /// Sets `/F`, the file containing the thread. When absent, the thread is in
  /// the current file.
  PdfActionThread setFile(PdfFileSpec file) {
    pdfRepresentation().put(PdfName.f, file.pdfRepresentation());
    return this;
  }

  /// Gets `/F` as written.
  Future<PdfObject?> getFile() async =>
      await pdfRepresentation().get(PdfName.f, true);

  /// Gets `/D` as written; it is a dictionary, an integer or a text string.
  Future<PdfObject?> getThread() async =>
      await pdfRepresentation().get(PdfName.d, true);

  /// Sets `/B` to the bead at [index] within the destination thread.
  PdfActionThread setBeadIndex(int index) {
    pdfRepresentation().put(PdfName.b, PdfNumber.fromInt(index));
    return this;
  }

  /// Sets `/B` to a bead dictionary.
  PdfActionThread setBead(PdfDictionary bead) {
    pdfRepresentation().put(PdfName.b, bead);
    return this;
  }

  /// Gets `/B` as written.
  Future<PdfObject?> getBead() async =>
      await pdfRepresentation().get(PdfName.b, true);
}
