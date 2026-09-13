import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/navigation/pdf_destination.dart';
import 'pdf_action.dart';

/// Go-to action, changing the view to a destination in the current document.
///
/// See ISO 32000-1:2008, 12.6.4.2, Table 199.
class PdfActionGoTo extends PdfAction {
  PdfActionGoTo(super.pdfObject);

  /// Creates a `/GoTo` action targeting [destination]. Table 199 accepts a
  /// name, a byte string or an array as `/D`.
  static PdfActionGoTo createGoTo(PdfObject destination) {
    PdfDictionary dict = PdfDictionary();
    dict.put(PdfName.type, PdfName.action);
    dict.put(PdfName.s, PdfName.goTo);
    dict.put(PdfName.d, destination);
    return PdfActionGoTo(dict);
  }

  /// Creates a `/GoTo` action from a typed destination.
  static PdfActionGoTo toDestination(PdfDestination destination) =>
      createGoTo(destination.pdfRepresentation());

  Future<PdfObject?> getDestination() async {
    return pdfRepresentation().get(PdfName.d);
  }

  /// Sets `/D`, the destination to jump to.
  PdfActionGoTo setDestination(PdfDestination destination) {
    pdfRepresentation().put(PdfName.d, destination.pdfRepresentation());
    return this;
  }
}
