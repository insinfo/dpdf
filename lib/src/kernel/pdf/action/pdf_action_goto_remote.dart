import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/filespec/pdf_file_spec.dart';
import 'package:dpdf/src/kernel/pdf/navigation/pdf_destination.dart';
import 'pdf_action.dart';

/// Remote go-to action, jumping to a destination in another PDF file.
///
/// See ISO 32000-1:2008, 12.6.4.3, Table 200.
class PdfActionGoToRemote extends PdfAction {
  PdfActionGoToRemote(super.pdfObject);

  /// Creates a `/GoToR` action. Both `/F` and `/D` are required by Table 200.
  ///
  /// When [destination] is an explicit destination array, its first element
  /// shall be a zero-based page number in the remote document rather than an
  /// indirect page reference; [PdfExplicitRemoteGoToDestination] builds that
  /// form.
  PdfActionGoToRemote.create(PdfFileSpec file, PdfDestination destination,
      {bool? newWindow})
      : super.ofType(PdfName.goToR) {
    setFile(file);
    setDestination(destination);
    if (newWindow != null) setNewWindow(newWindow);
  }

  /// Creates a `/GoToR` action from a plain file name string.
  PdfActionGoToRemote.toFile(String fileName, PdfDestination destination,
      {bool? newWindow})
      : super.ofType(PdfName.goToR) {
    pdfRepresentation()
        .put(PdfName.f, PdfFileSpec.external(fileName).pdfRepresentation());
    setDestination(destination);
    if (newWindow != null) setNewWindow(newWindow);
  }

  /// Sets `/F`, the file in which the destination is located.
  PdfActionGoToRemote setFile(PdfFileSpec file) {
    pdfRepresentation().put(PdfName.f, file.pdfRepresentation());
    return this;
  }

  /// Gets `/F` as written.
  Future<PdfObject?> getFile() async =>
      await pdfRepresentation().get(PdfName.f, true);

  /// Gets the file name of `/F`, accepting the string and dictionary forms.
  Future<String?> getFileName() async =>
      await readFileSpecificationName(await getFile());

  /// Sets `/D`, the destination in the remote document.
  PdfActionGoToRemote setDestination(PdfDestination destination) {
    pdfRepresentation().put(PdfName.d, destination.pdfRepresentation());
    return this;
  }

  /// Gets `/D` as written.
  Future<PdfObject?> getDestination() async =>
      await pdfRepresentation().get(PdfName.d, true);

  /// Sets `/NewWindow`.
  PdfActionGoToRemote setNewWindow(bool newWindow) {
    pdfRepresentation().put(PdfName.intern('NewWindow'), PdfBoolean(newWindow));
    return this;
  }

  /// Gets `/NewWindow`. Table 200 leaves the behaviour to the reader's
  /// preference when the entry is absent, so null is returned.
  Future<bool?> getNewWindow() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('NewWindow')))
          ?.getValue();

  /// Wraps an existing dictionary, checking `/S`.
  static PdfActionGoToRemote wrap(PdfDictionary dictionary) =>
      PdfActionGoToRemote(dictionary);
}
