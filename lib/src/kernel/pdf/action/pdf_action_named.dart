import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'pdf_action.dart';

/// Named action, executing an action predefined by the conforming reader.
///
/// See ISO 32000-1:2008, 12.6.4.11, Tables 211 and 212.
class PdfActionNamed extends PdfAction {
  /// Go to the next page of the document.
  static final PdfName nextPage = PdfName.intern('NextPage');

  /// Go to the previous page of the document.
  static final PdfName previousPage = PdfName.intern('PrevPage');

  /// Go to the first page of the document.
  static final PdfName firstPage = PdfName.intern('FirstPage');

  /// Go to the last page of the document.
  static final PdfName lastPage = PdfName.intern('LastPage');

  /// The named actions every conforming reader shall support (Table 211).
  static final Set<String> standardNames = {
    nextPage.getValue(),
    previousPage.getValue(),
    firstPage.getValue(),
    lastPage.getValue(),
  };

  PdfActionNamed(super.pdfObject);

  /// Creates a `/Named` action. Table 211 allows non-standard names, so any
  /// name is accepted; [standardNames] lists the portable ones.
  PdfActionNamed.create(PdfName name) : super.ofType(PdfName.named) {
    pdfRepresentation().put(PdfName.n, name);
  }

  /// Gets `/N`, the name of the action to perform.
  Future<PdfName?> getName() async =>
      await pdfRepresentation().nameEntry(PdfName.n);

  /// True when `/N` is one of the four standard names of Table 211.
  Future<bool> isStandard() async {
    final name = await getName();
    return name != null && standardNames.contains(name.getValue());
  }
}
