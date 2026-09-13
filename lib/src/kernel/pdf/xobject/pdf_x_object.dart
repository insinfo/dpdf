import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';

abstract class PdfXObject extends PdfObjectWrapper<PdfStream> {
  /// The `/OC` key of ISO 32000-1, clause 8.11.3.3.
  static final PdfName oc = PdfName.intern('OC');

  PdfXObject(PdfStream pdfObject) : super(pdfObject);

  @override
  bool requiresIndirectStorage() => true;

  double getWidth();
  double getHeight();

  /// The `/OC` entry, ISO 32000-1, clause 8.11.3.3.
  ///
  /// A form or image XObject that carries one is drawn only when the group or
  /// membership dictionary it names is visible, on top of whatever visibility
  /// already applies where the `Do` operator appears. The raw entry is
  /// returned so that callers keep the indirect reference the layer API needs.
  Future<PdfObject?> getOptionalContent() async {
    return pdfRepresentation().get(oc, false);
  }

  /// Whether this XObject declares itself optional.
  bool hasOptionalContent() => pdfRepresentation().containsKey(oc);

  /// Makes this XObject optional, controlled by [group].
  ///
  /// [group] is an optional content group or a membership dictionary; it has
  /// to be an indirect object, so its reference is written when it has one.
  void setOptionalContent(PdfDictionary group) {
    final reference = group.indirectHandle();
    pdfRepresentation().put(oc, reference ?? group);
    markChanged();
  }

  /// Drops the `/OC` entry, making this XObject unconditionally visible.
  void removeOptionalContent() {
    pdfRepresentation().remove(oc);
    markChanged();
  }
}
