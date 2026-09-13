import '../pdf_date.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_string.dart';

import 'pdf_annotation.dart';
import 'pdf_popup_annotation.dart';

/// Base class for the markup annotations of ISO 32000-1:2008, 12.5.6.2.
///
/// Adds the entries of Table 170 that every markup annotation may carry.
abstract class PdfMarkupAnnotation extends PdfAnnotation {
  /// `/RT` value: the annotation is a reply to the annotation named by `/IRT`.
  static final PdfName replyTypeReply = PdfName.intern('R');

  /// `/RT` value: the annotation is grouped with the one named by `/IRT`.
  static final PdfName replyTypeGroup = PdfName.intern('Group');

  PdfMarkupAnnotation(super.pdfObject);

  PdfMarkupAnnotation.fromRect(super.rect) : super.fromRect();

  /// Sets `/T`, the text label shown in the title bar of the pop-up window.
  PdfMarkupAnnotation setTitle(PdfString title) {
    put(PdfName.t, title);
    return this;
  }

  /// Gets `/T`.
  Future<PdfString?> getTitle() async =>
      await pdfRepresentation().stringEntry(PdfName.t);

  /// Sets `/Popup`. The pop-up annotation's `/Parent` is set to this
  /// annotation, as required by Table 183.
  PdfMarkupAnnotation setPopup(PdfPopupAnnotation popup) {
    popup.setParentAnnotation(this);
    put(PdfName.popup, popup.pdfRepresentation());
    return this;
  }

  /// Gets `/Popup`.
  Future<PdfPopupAnnotation?> getPopup() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.popup);
    return dictionary == null ? null : PdfPopupAnnotation(dictionary);
  }

  /// Sets `/CA`, the constant opacity in the range 0 to 1. Default 1.0.
  PdfMarkupAnnotation setOpacity(double opacity) {
    if (opacity < 0 || opacity > 1) {
      throw ArgumentError.value(
          opacity, 'opacity', 'Markup annotation /CA must lie in [0, 1]');
    }
    put(PdfName.caUppercase, PdfNumber(opacity));
    return this;
  }

  /// Gets `/CA`; the default is 1.0 per Table 170.
  Future<double> getOpacity() async {
    return (await pdfRepresentation().numberEntry(PdfName.caUppercase))
            ?.getValue() ??
        1.0;
  }

  /// Sets `/RC`, the rich text string shown in the pop-up window. The value
  /// may be a text string or a text stream (Table 170).
  PdfMarkupAnnotation setRichText(PdfObject richText) {
    put(PdfName.intern('RC'), richText);
    return this;
  }

  /// Gets `/RC` as written.
  Future<PdfObject?> getRichText() async =>
      await pdfRepresentation().get(PdfName.intern('RC'), true);

  /// Sets `/CreationDate`.
  PdfMarkupAnnotation setCreationDate(PdfDate date) {
    put(PdfName.creationDate, PdfString(date.getValue()));
    return this;
  }

  /// Gets `/CreationDate` as written.
  Future<PdfString?> getCreationDate() async =>
      await pdfRepresentation().stringEntry(PdfName.creationDate);

  /// Sets `/IRT`, a reference to the annotation this one is "in reply to".
  /// Both annotations shall be on the same page (Table 170).
  PdfMarkupAnnotation setInReplyTo(PdfAnnotation annotation) {
    put(PdfName.intern('IRT'), annotation.pdfRepresentation());
    return this;
  }

  /// Gets `/IRT`.
  Future<PdfDictionary?> getInReplyTo() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('IRT'));

  /// Sets `/Subj`, a short description of the subject of the annotation.
  PdfMarkupAnnotation setSubject(PdfString subject) {
    put(PdfName.intern('Subj'), subject);
    return this;
  }

  /// Gets `/Subj`.
  Future<PdfString?> getSubject() async =>
      await pdfRepresentation().stringEntry(PdfName.intern('Subj'));

  /// Sets `/RT`, meaningful only when `/IRT` is present. Valid values are
  /// [replyTypeReply] and [replyTypeGroup] (Table 170).
  PdfMarkupAnnotation setReplyType(PdfName replyType) {
    if (replyType != replyTypeReply && replyType != replyTypeGroup) {
      throw ArgumentError.value(
          replyType, 'replyType', 'Markup /RT shall be /R or /Group');
    }
    put(PdfName.intern('RT'), replyType);
    return this;
  }

  /// Gets `/RT`; the default is [replyTypeReply] per Table 170.
  Future<PdfName> getReplyType() async =>
      await pdfRepresentation().nameEntry(PdfName.intern('RT')) ??
      replyTypeReply;

  /// Sets `/IT`, the intent of the markup annotation.
  PdfMarkupAnnotation setIntent(PdfName intent) {
    put(PdfName.intern('IT'), intent);
    return this;
  }

  /// Gets `/IT`.
  Future<PdfName?> getIntent() async =>
      await pdfRepresentation().nameEntry(PdfName.intern('IT'));

  /// Sets `/ExData`, an external data dictionary (Table 170). `/Type` is set
  /// to `/ExData` and `/Subtype` is required by the specification.
  PdfMarkupAnnotation setExternalData(PdfDictionary data) {
    data.put(PdfName.type, PdfName.intern('ExData'));
    put(PdfName.intern('ExData'), data);
    return this;
  }

  /// Gets `/ExData`.
  Future<PdfDictionary?> getExternalData() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('ExData'));
}
