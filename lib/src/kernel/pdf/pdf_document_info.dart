import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_object_wrapper.dart';
import 'pdf_string.dart';
import '../../io/font/pdf_encodings.dart';
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
    _storeText(PdfName.title, title);
  }

  /// Sets the author of the document.
  void setAuthor(String author) {
    _storeText(PdfName.author, author);
  }

  /// Sets the subject of the document.
  void setSubject(String subject) {
    _storeText(PdfName.subject, subject);
  }

  /// Sets the keywords of the document.
  void setKeywords(String keywords) {
    _storeText(PdfName.keywords, keywords);
  }

  /// Sets the creator of the document.
  void setCreator(String creator) {
    _storeText(PdfName.creator, creator);
  }

  /// Sets the producer of the document.
  void setProducer(String producer) {
    _storeText(PdfName.producer, producer);
  }

  /// Sets the creation date of the document.
  void setCreationDate(DateTime date) {
    _storeText(PdfName.creationDate, DateTimeUtil.formatPdfDate(date));
  }

  /// Sets the modification date of the document.
  void setModDate(DateTime date) {
    _storeText(PdfName.modDate, DateTimeUtil.formatPdfDate(date));
  }

  /// Adds the current date as validation date.
  void addCreationDate() {
    setCreationDate(DateTime.now());
  }

  /// Adds the current date as modification date.
  void addModDate() {
    setModDate(DateTime.now());
  }

  void _storeText(PdfName key, String value) {
    final encoded = value.codeUnits.every((unit) => unit < 128)
        ? PdfString(value)
        : PdfString.fromBytes(
            PdfEncodings.convertToBytes(value, PdfEncodings.UNICODE_BIG));
    pdfRepresentation().put(key, encoded);
    pdfRepresentation().markChanged();
  }

  @override
  bool requiresIndirectStorage() => true;
}
