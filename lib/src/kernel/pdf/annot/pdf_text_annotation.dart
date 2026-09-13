import '../pdf_boolean.dart';
import '../pdf_name.dart';
import '../pdf_string.dart';

import 'pdf_markup_annotation.dart';

/// Text ("sticky note") annotation.
///
/// See ISO 32000-1:2008, 12.5.6.4, Table 172.
class PdfTextAnnotation extends PdfMarkupAnnotation {
  // Standard icon names listed in Table 172.
  static final PdfName iconComment = PdfName.intern('Comment');
  static final PdfName iconKey = PdfName.intern('Key');
  static final PdfName iconNote = PdfName.intern('Note');
  static final PdfName iconHelp = PdfName.intern('Help');
  static final PdfName iconNewParagraph = PdfName.intern('NewParagraph');
  static final PdfName iconParagraph = PdfName.intern('Paragraph');
  static final PdfName iconInsert = PdfName.intern('Insert');

  /// State models of Table 171.
  static const String stateModelMarked = 'Marked';
  static const String stateModelReview = 'Review';

  PdfTextAnnotation(super.pdfObject);

  PdfTextAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.text);
  }

  @override
  PdfName getSubtype() => PdfName.text;

  /// Sets `/Open`, whether the annotation is initially displayed open.
  PdfTextAnnotation setOpen(bool open) {
    put(PdfName.intern('Open'), PdfBoolean(open));
    return this;
  }

  /// Gets `/Open`; the default is false (closed) per Table 172.
  Future<bool> isOpen() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('Open')))
          ?.getValue() ??
      false;

  /// Sets `/Name`, the icon name used to display the annotation.
  PdfTextAnnotation setIconName(PdfName name) {
    put(PdfName.name, name);
    return this;
  }

  /// Gets `/Name`; the default is `/Note` per Table 172.
  Future<PdfName> getIconName() async =>
      await pdfRepresentation().nameEntry(PdfName.name) ?? iconNote;

  /// Sets `/State` and `/StateModel` together. Table 172 makes `/StateModel`
  /// required whenever `/State` is present, so both are always written.
  PdfTextAnnotation setState(String state, String stateModel) {
    put(PdfName.intern('State'), PdfString(state));
    put(PdfName.intern('StateModel'), PdfString(stateModel));
    return this;
  }

  /// Gets `/State`.
  Future<String?> getState() async =>
      (await pdfRepresentation().stringEntry(PdfName.intern('State')))
          ?.getValue();

  /// Gets `/StateModel`.
  Future<String?> getStateModel() async =>
      (await pdfRepresentation().stringEntry(PdfName.intern('StateModel')))
          ?.getValue();
}
