import '../pdf_dictionary.dart';
import '../pdf_name.dart';

import '../filespec/pdf_file_spec.dart';
import 'pdf_markup_annotation.dart';

/// File attachment annotation.
///
/// See ISO 32000-1:2008, 12.5.6.15, Table 184.
class PdfFileAttachmentAnnotation extends PdfMarkupAnnotation {
  // Standard icon names required by Table 184.
  static final PdfName iconGraph = PdfName.intern('Graph');
  static final PdfName iconPushPin = PdfName.intern('PushPin');
  static final PdfName iconPaperclip = PdfName.intern('Paperclip');
  static final PdfName iconTag = PdfName.intern('Tag');

  PdfFileAttachmentAnnotation(super.pdfObject);

  /// Creates a file attachment annotation. `/FS` is required by Table 184.
  PdfFileAttachmentAnnotation.fromRect(super.rect, PdfFileSpec fileSpec)
      : super.fromRect() {
    put(PdfName.subtype, PdfName.fileAttachment);
    setFileSpec(fileSpec);
  }

  @override
  PdfName getSubtype() => PdfName.fileAttachment;

  /// Sets `/FS`, the file associated with the annotation.
  PdfFileAttachmentAnnotation setFileSpec(PdfFileSpec fileSpec) {
    put(PdfName.intern('FS'), fileSpec.pdfRepresentation());
    return this;
  }

  /// Gets `/FS`.
  Future<PdfFileSpec?> getFileSpec() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfName.intern('FS'));
    return dictionary == null ? null : PdfFileSpec(dictionary);
  }

  /// Sets `/Name`, the icon shown for the attachment.
  PdfFileAttachmentAnnotation setIconName(PdfName name) {
    put(PdfName.name, name);
    return this;
  }

  /// Gets `/Name`; the default is `/PushPin` per Table 184.
  Future<PdfName> getIconName() async =>
      await pdfRepresentation().nameEntry(PdfName.name) ?? iconPushPin;

  /// Reads the attached file specification dictionary as written.
  Future<PdfDictionary?> getFileSpecDictionary() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('FS'));
}
