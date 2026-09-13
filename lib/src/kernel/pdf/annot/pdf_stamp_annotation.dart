import '../pdf_name.dart';

import 'pdf_markup_annotation.dart';

/// Rubber stamp annotation.
///
/// See ISO 32000-1:2008, 12.5.6.12, Table 181.
class PdfStampAnnotation extends PdfMarkupAnnotation {
  // The standard icon names required by Table 181.
  static final PdfName iconApproved = PdfName.intern('Approved');
  static final PdfName iconExperimental = PdfName.intern('Experimental');
  static final PdfName iconNotApproved = PdfName.intern('NotApproved');
  static final PdfName iconAsIs = PdfName.intern('AsIs');
  static final PdfName iconExpired = PdfName.intern('Expired');
  static final PdfName iconNotForPublicRelease =
      PdfName.intern('NotForPublicRelease');
  static final PdfName iconConfidential = PdfName.intern('Confidential');
  static final PdfName iconFinal = PdfName.intern('Final');
  static final PdfName iconSold = PdfName.intern('Sold');
  static final PdfName iconDepartmental = PdfName.intern('Departmental');
  static final PdfName iconForComment = PdfName.intern('ForComment');
  static final PdfName iconTopSecret = PdfName.intern('TopSecret');
  static final PdfName iconDraft = PdfName.intern('Draft');
  static final PdfName iconForPublicRelease =
      PdfName.intern('ForPublicRelease');

  /// Every standard stamp name listed in Table 181.
  static final Set<String> standardIcons = {
    iconApproved.getValue(),
    iconExperimental.getValue(),
    iconNotApproved.getValue(),
    iconAsIs.getValue(),
    iconExpired.getValue(),
    iconNotForPublicRelease.getValue(),
    iconConfidential.getValue(),
    iconFinal.getValue(),
    iconSold.getValue(),
    iconDepartmental.getValue(),
    iconForComment.getValue(),
    iconTopSecret.getValue(),
    iconDraft.getValue(),
    iconForPublicRelease.getValue(),
  };

  PdfStampAnnotation(super.pdfObject);

  PdfStampAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.stamp);
  }

  @override
  PdfName getSubtype() => PdfName.stamp;

  /// Sets `/Name`, the icon name. Table 181 allows names beyond the standard
  /// ones, so arbitrary names are accepted.
  PdfStampAnnotation setIconName(PdfName name) {
    put(PdfName.name, name);
    return this;
  }

  /// Gets `/Name`; the default is `/Draft` per Table 181.
  Future<PdfName> getIconName() async =>
      await pdfRepresentation().nameEntry(PdfName.name) ?? iconDraft;
}
