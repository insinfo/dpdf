import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import '../viewer/pdf_transition.dart';
import 'pdf_action.dart';

/// Transition action, updating the display using a transition dictionary.
///
/// See ISO 32000-1:2008, 12.6.4.14, Table 215.
class PdfActionTransition extends PdfAction {
  PdfActionTransition(super.pdfObject);

  /// Creates a `/Trans` action. `/Trans` is required by Table 215.
  PdfActionTransition.create(PdfDictionary transition)
      : super.ofType(PdfName.intern('Trans')) {
    setTransition(transition);
  }

  /// Sets `/Trans`, the transition dictionary (Table 162).
  PdfActionTransition setTransition(PdfDictionary transition) {
    transition.put(PdfName.type, PdfName.intern('Trans'));
    pdfRepresentation().put(PdfName.intern('Trans'), transition);
    return this;
  }

  /// Creates a `/Trans` action carrying [transition].
  PdfActionTransition.ofTransition(PdfTransition transition)
      : super.ofType(PdfName.intern('Trans')) {
    setTransition(transition.pdfRepresentation());
  }

  /// Gets `/Trans` as a raw dictionary.
  Future<PdfDictionary?> getTransition() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('Trans'));

  /// Gets `/Trans` wrapped in [PdfTransition], which validates the entries
  /// each style of Table 162 actually accepts.
  Future<PdfTransition?> getPageTransition() async {
    final dictionary = await getTransition();
    return dictionary == null ? null : PdfTransition.wrap(dictionary);
  }
}
