import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';

import 'pdf_annotation.dart';

/// Pop-up annotation.
///
/// See ISO 32000-1:2008, 12.5.6.14, Table 183. A pop-up annotation is not a
/// markup annotation (Table 169); it is associated with a markup annotation
/// through the parent's `/Popup` entry.
class PdfPopupAnnotation extends PdfAnnotation {
  PdfPopupAnnotation(super.pdfObject);

  PdfPopupAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.popup);
  }

  @override
  PdfName getSubtype() => PdfName.popup;

  /// Sets `/Parent`, the markup annotation this pop-up belongs to. Table 183
  /// requires an indirect reference, which [PdfAnnotation] already enforces
  /// for every annotation dictionary.
  PdfPopupAnnotation setParentAnnotation(PdfAnnotation parent) {
    put(PdfName.parent, parent.pdfRepresentation());
    return this;
  }

  /// Gets `/Parent`.
  Future<PdfDictionary?> getParentAnnotation() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.parent);

  /// Sets `/Open`, whether the pop-up is initially displayed open.
  PdfPopupAnnotation setOpen(bool open) {
    put(PdfName.intern('Open'), PdfBoolean(open));
    return this;
  }

  /// Gets `/Open`; the default is false (closed) per Table 183.
  Future<bool> isOpen() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('Open')))
          ?.getValue() ??
      false;
}
