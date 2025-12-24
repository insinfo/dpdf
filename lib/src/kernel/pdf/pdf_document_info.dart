import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_object_wrapper.dart';
import 'pdf_string.dart';
// import 'pdf_document.dart';
import 'package:dpdf/src/commons/utils/date_time_util.dart';

/// Document information dictionary.
class PdfDocumentInfo extends PdfObjectWrapper<PdfDictionary> {
  /// Creates a [PdfDocumentInfo] wrapper.
  PdfDocumentInfo(PdfDictionary pdfObject) : super(pdfObject);

  /// Creates a new [PdfDocumentInfo].
  PdfDocumentInfo.create() : super(PdfDictionary());

  /// Sets the title of the document.
  void setTitle(String title) {
    getPdfObject().put(PdfName.title, PdfString(title));
  }

  /// Sets the author of the document.
  void setAuthor(String author) {
    getPdfObject().put(PdfName.author, PdfString(author));
  }

  /// Sets the subject of the document.
  void setSubject(String subject) {
    getPdfObject().put(PdfName.subject, PdfString(subject));
  }

  /// Sets the keywords of the document.
  void setKeywords(String keywords) {
    getPdfObject().put(PdfName.keywords, PdfString(keywords));
  }

  /// Sets the creator of the document.
  void setCreator(String creator) {
    getPdfObject().put(PdfName.creator, PdfString(creator));
  }

  /// Sets the producer of the document.
  void setProducer(String producer) {
    getPdfObject().put(PdfName.producer, PdfString(producer));
  }

  /// Sets the creation date of the document.
  void setCreationDate(DateTime date) {
    // TODO: Usar DateTimeUtil formatado para PDF string
    getPdfObject()
        .put(PdfName.creationDate, PdfString(DateTimeUtil.formatPdfDate(date)));
  }

  /// Sets the modification date of the document.
  void setModDate(DateTime date) {
    getPdfObject()
        .put(PdfName.modDate, PdfString(DateTimeUtil.formatPdfDate(date)));
  }

  @override
  bool isWrappedObjectMustBeIndirect() => true;
}
