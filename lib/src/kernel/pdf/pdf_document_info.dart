import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_object_wrapper.dart';
import 'pdf_string.dart';
// import 'pdf_document.dart';
import 'package:pdfcraft/src/commons/utils/date_time_util.dart';

/// Document information dictionary.
class CraftPdfDocumentInfo extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  /// Creates a [PdfDocumentInfo] wrapper.
  CraftPdfDocumentInfo(CraftPdfDictionary pdfObject) : super(pdfObject);

  /// Creates a new [PdfDocumentInfo].
  CraftPdfDocumentInfo.create() : super(CraftPdfDictionary());

  /// Sets the title of the document.
  void setTitle(String title) {
    pdfRepresentation().put(CraftPdfName.title, CraftPdfString(title));
  }

  /// Sets the author of the document.
  void setAuthor(String author) {
    pdfRepresentation().put(CraftPdfName.author, CraftPdfString(author));
  }

  /// Sets the subject of the document.
  void setSubject(String subject) {
    pdfRepresentation().put(CraftPdfName.subject, CraftPdfString(subject));
  }

  /// Sets the keywords of the document.
  void setKeywords(String keywords) {
    pdfRepresentation().put(CraftPdfName.keywords, CraftPdfString(keywords));
  }

  /// Sets the creator of the document.
  void setCreator(String creator) {
    pdfRepresentation().put(CraftPdfName.creator, CraftPdfString(creator));
  }

  /// Sets the producer of the document.
  void setProducer(String producer) {
    pdfRepresentation().put(CraftPdfName.producer, CraftPdfString(producer));
  }

  /// Sets the creation date of the document.
  void setCreationDate(DateTime date) {
    pdfRepresentation().put(CraftPdfName.creationDate,
        CraftPdfString(CraftDateTimeUtil.formatPdfDate(date)));
  }

  /// Sets the modification date of the document.
  void setModDate(DateTime date) {
    pdfRepresentation().put(CraftPdfName.modDate,
        CraftPdfString(CraftDateTimeUtil.formatPdfDate(date)));
  }

  /// Adds the current date as validation date.
  void addCreationDate() {
    setCreationDate(DateTime.now());
  }

  /// Adds the current date as modification date.
  void addModDate() {
    setModDate(DateTime.now());
  }

  @override
  bool requiresIndirectStorage() => true;
}
