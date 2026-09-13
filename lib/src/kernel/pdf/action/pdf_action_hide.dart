import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'pdf_action.dart';

/// Hide action, setting or clearing the Hidden flag of annotations.
///
/// See ISO 32000-1:2008, 12.6.4.10, Table 210.
class PdfActionHide extends PdfAction {
  PdfActionHide(super.pdfObject);

  /// Creates a `/Hide` action targeting a single annotation dictionary.
  PdfActionHide.annotation(PdfDictionary annotation, {bool hide = true})
      : super.ofType(PdfName.intern('Hide')) {
    pdfRepresentation().put(PdfName.t, annotation);
    _writeHide(hide);
  }

  /// Creates a `/Hide` action targeting the widget annotations of the field
  /// whose fully qualified name is [fieldName].
  PdfActionHide.field(String fieldName, {bool hide = true})
      : super.ofType(PdfName.intern('Hide')) {
    pdfRepresentation().put(PdfName.t, PdfString(fieldName));
    _writeHide(hide);
  }

  /// Creates a `/Hide` action targeting several annotations or field names.
  PdfActionHide.targets(List<PdfObject> targets, {bool hide = true})
      : super.ofType(PdfName.intern('Hide')) {
    if (targets.isEmpty) {
      throw ArgumentError.value(
          targets, 'targets', 'Hide actions require at least one target');
    }
    pdfRepresentation().put(PdfName.t, PdfArray.fromList(targets));
    _writeHide(hide);
  }

  void _writeHide(bool hide) {
    // Table 210 gives /H a default of true; only the non-default is written.
    if (!hide) {
      pdfRepresentation().put(PdfName.intern('H'), PdfBoolean(false));
    }
  }

  /// Sets `/H`, true to hide the annotation and false to show it.
  PdfActionHide setHide(bool hide) {
    pdfRepresentation().put(PdfName.intern('H'), PdfBoolean(hide));
    return this;
  }

  /// Gets `/H`; the default is true per Table 210.
  Future<bool> isHide() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('H')))
          ?.getValue() ??
      true;

  /// Gets `/T` as written; it is a dictionary, a text string or an array.
  Future<PdfObject?> getTargets() async =>
      await pdfRepresentation().get(PdfName.t, true);
}
