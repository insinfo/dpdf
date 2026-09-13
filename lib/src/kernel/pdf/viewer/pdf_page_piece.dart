import '../../exceptions/pdf_exception.dart';
import '../pdf_date.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';

/// A data dictionary of ISO 32000-1:2008, 14.5, Table 319.
///
/// It holds one conforming product's private data for a document, a page or a
/// form XObject. `/LastModified` is required and says when that product last
/// altered the content; `/Private` carries the data itself and may be any
/// object, typically a dictionary.
class PdfApplicationData extends PdfObjectWrapper<PdfDictionary> {
  /// `/LastModified`.
  static final PdfName lastModified = PdfName.intern('LastModified');

  /// `/Private`.
  static final PdfName private = PdfName.intern('Private');

  /// Wraps [dictionary], or starts an empty data dictionary.
  PdfApplicationData([PdfDictionary? dictionary])
      : super(dictionary ?? PdfDictionary());

  /// Starts a data dictionary already carrying the required `/LastModified`.
  PdfApplicationData.modifiedAt(DateTime moment) : super(PdfDictionary()) {
    setLastModified(moment);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/LastModified`, which Table 319 requires.
  PdfApplicationData setLastModified(DateTime moment) {
    pdfRepresentation()
        .put(lastModified, PdfString(PdfDate(moment).getValue()));
    markChanged();
    return this;
  }

  /// Gets `/LastModified`, or `null` when the required entry is missing.
  ///
  /// The result is the instant the stored date denotes, in UTC when the date
  /// carries a UTC offset. 14.5 warns that some platforms store only an
  /// approximate value or mishandle time zones, so modification dates shall be
  /// compared for equality only, never ordered.
  Future<DateTime?> getLastModified() async {
    final value = await pdfRepresentation().stringEntry(lastModified);
    if (value == null) return null;
    try {
      return PdfDate.decode(value.decodeMappingText());
    } on FormatException catch (error) {
      throw PdfException('/LastModified is not a PDF date: ${error.message}');
    }
  }

  /// Sets `/Private`, the private data of the conforming product.
  PdfApplicationData setPrivate(PdfObject data) {
    pdfRepresentation().put(private, data);
    markChanged();
    return this;
  }

  /// Gets `/Private`, resolved through any indirect reference, or `null`.
  Future<PdfObject?> getPrivate() => pdfRepresentation().get(private, true);
}

/// A page-piece dictionary of ISO 32000-1:2008, 14.5, Table 318.
///
/// It is the value of `/PieceInfo` in a page object (Table 30), a form XObject
/// (Table 95) or, since PDF 1.4, the document catalog (Table 28). Each entry is
/// keyed by the name of a conforming product or of a well known data type, and
/// its value is a data dictionary ([PdfApplicationData], Table 319).
class PdfPagePiece extends PdfObjectWrapper<PdfDictionary> {
  /// `/PieceInfo`, the key under which a page-piece dictionary is stored.
  static final PdfName pieceInfo = PdfName.intern('PieceInfo');

  /// Wraps [dictionary], or starts an empty page-piece dictionary.
  PdfPagePiece([PdfDictionary? dictionary])
      : super(dictionary ?? PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Stores [data] under [producer], the name of the conforming product or of
  /// a well known data type.
  ///
  /// Table 319 makes `/LastModified` required, so a data dictionary without it
  /// is rejected rather than written out incomplete.
  PdfPagePiece setData(String producer, PdfApplicationData data) {
    if (producer.isEmpty) {
      throw PdfException(
          'A page-piece entry is keyed by a conforming product name, which '
          'cannot be empty.');
    }
    if (!data
        .pdfRepresentation()
        .containsKey(PdfApplicationData.lastModified)) {
      throw PdfException(
          'Table 319 requires /LastModified in the data dictionary stored '
          'under /$producer.');
    }
    pdfRepresentation().put(PdfName.intern(producer), data.pdfRepresentation());
    markChanged();
    return this;
  }

  /// Gets the data dictionary stored under [producer], or `null`.
  Future<PdfApplicationData?> getData(String producer) async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfName.intern(producer));
    return dictionary == null ? null : PdfApplicationData(dictionary);
  }

  /// The conforming product names this page-piece dictionary carries.
  List<String> producers() =>
      pdfRepresentation().keySet().map((key) => key.getValue()).toList();

  /// Removes the data stored under [producer].
  PdfPagePiece removeData(String producer) {
    pdfRepresentation().remove(PdfName.intern(producer));
    markChanged();
    return this;
  }
}
