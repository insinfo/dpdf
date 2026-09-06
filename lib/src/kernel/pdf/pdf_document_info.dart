import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_object_wrapper.dart';
import 'pdf_string.dart';
import '../../io/font/pdf_encodings.dart';
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
    _storeText(CraftPdfName.title, title);
  }

  /// Sets the author of the document.
  void setAuthor(String author) {
    _storeText(CraftPdfName.author, author);
  }

  /// Sets the subject of the document.
  void setSubject(String subject) {
    _storeText(CraftPdfName.subject, subject);
  }

  /// Sets the keywords of the document.
  void setKeywords(String keywords) {
    _storeText(CraftPdfName.keywords, keywords);
  }

  /// Sets the creator of the document.
  void setCreator(String creator) {
    _storeText(CraftPdfName.creator, creator);
  }

  /// Sets the producer of the document.
  void setProducer(String producer) {
    _storeText(CraftPdfName.producer, producer);
  }

  /// Sets the creation date of the document.
  void setCreationDate(DateTime date) {
    _storeText(
        CraftPdfName.creationDate, CraftDateTimeUtil.formatPdfDate(date));
  }

  /// Sets the modification date of the document.
  void setModDate(DateTime date) {
    _storeText(CraftPdfName.modDate, CraftDateTimeUtil.formatPdfDate(date));
  }

  /// Adds the current date as validation date.
  void addCreationDate() {
    setCreationDate(DateTime.now());
  }

  /// Adds the current date as modification date.
  void addModDate() {
    setModDate(DateTime.now());
  }

  void _storeText(CraftPdfName key, String value) {
    final encoded = value.codeUnits.every((unit) => unit < 128)
        ? CraftPdfString(value)
        : CraftPdfString.fromBytes(CraftPdfEncodings.convertToBytes(
            value, CraftPdfEncodings.UNICODE_BIG));
    pdfRepresentation().put(key, encoded);
    pdfRepresentation().markChanged();
  }

  @override
  bool requiresIndirectStorage() => true;
}
