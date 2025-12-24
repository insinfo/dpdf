import 'pdf_document.dart';
import 'pdf_reader.dart';

/// PDF object type constants.
class PdfObjectType {
  PdfObjectType._();

  /// Array type.
  static const int array = 1;

  /// Boolean type.
  static const int boolean = 2;

  /// Dictionary type.
  static const int dictionary = 3;

  /// Literal type.
  static const int literal = 4;

  /// Indirect reference type.
  static const int indirectReference = 5;

  /// Name type.
  static const int name = 6;

  /// Null type.
  static const int nullType = 7;

  /// Number type.
  static const int number = 8;

  /// Stream type.
  static const int stream = 9;

  /// String type.
  static const int string = 10;
}

/// Base class for all PDF objects.
///
/// All PDF primitive types (boolean, numbers, strings, names, arrays,
/// dictionaries, streams, null, and indirect references) extend this class.
abstract class PdfObject {
  /// Indicates if the object has been flushed.
  static const int flushed = 1;

  /// Indicates that the indirect reference could be reused or marked as free.
  static const int free = 1 << 1;

  /// Indicates that definition of the indirect reference is not found yet.
  static const int reading = 1 << 2;

  /// Indicates that object changed (used in append mode).
  static const int modified = 1 << 3;

  /// Indicates ObjectStream from original document.
  static const int originalObjectStream = 1 << 4;

  /// Marks objects that shall be written to the output document.
  static const int mustBeFlushed = 1 << 5;

  /// Indicates that the object shall be indirect when written.
  static const int mustBeIndirect = 1 << 6;

  /// Indicates that we don't want to release this object.
  static const int forbidRelease = 1 << 7;

  /// Indicates that we don't want to write this object.
  static const int readOnly = 1 << 8;

  /// Indicates that this object is not encrypted.
  static const int unencrypted = 1 << 9;

  /// If object is flushed the indirect reference is kept here.
  PdfIndirectReference? indirectReference;

  /// State flags for this object.
  int _state = 0;

  /// Gets object type.
  int getObjectType();

  /// Flushes the object to the document.
  void flush([bool canBeInObjStm = true]) {
    // Basic implementation - will be expanded when PdfDocument is ported
    if (isFlushed() || getIndirectReference() == null) {
      return;
    }
    // TODO: Implement full flush when PdfDocument is available
  }

  /// Gets the indirect reference associated with the object.
  PdfIndirectReference? getIndirectReference() {
    return indirectReference;
  }

  /// Checks if object is indirect.
  bool isIndirect() {
    return indirectReference != null || checkState(mustBeIndirect);
  }

  /// Indicates if the object has been flushed.
  bool isFlushed() {
    final ref = getIndirectReference();
    return ref != null && ref.checkState(flushed);
  }

  /// Indicates if the object has been modified.
  bool isModified() {
    final ref = getIndirectReference();
    return ref != null && ref.checkState(modified);
  }

  /// Creates a clone of the object.
  PdfObject clone();

  /// Sets the modified flag.
  PdfObject setModified() {
    if (indirectReference != null) {
      indirectReference!.setState(modified);
      setState(forbidRelease);
    }
    return this;
  }

  /// Checks if release is forbidden.
  bool isReleaseForbidden() {
    return checkState(forbidRelease);
  }

  /// Releases the object.
  void release() {
    if (isReleaseForbidden()) {
      return;
    }
    if (indirectReference != null && !indirectReference!.checkState(flushed)) {
      indirectReference = null;
      setState(readOnly);
    }
  }

  /// Checks if this is a PdfNull.
  bool isNull() => getObjectType() == PdfObjectType.nullType;

  /// Checks if this is a PdfBoolean.
  bool isBoolean() => getObjectType() == PdfObjectType.boolean;

  /// Checks if this is a PdfNumber.
  bool isNumber() => getObjectType() == PdfObjectType.number;

  /// Checks if this is a PdfString.
  bool isString() => getObjectType() == PdfObjectType.string;

  /// Checks if this is a PdfName.
  bool isName() => getObjectType() == PdfObjectType.name;

  /// Checks if this is a PdfArray.
  bool isArray() => getObjectType() == PdfObjectType.array;

  /// Checks if this is a PdfDictionary.
  bool isDictionary() => getObjectType() == PdfObjectType.dictionary;

  /// Checks if this is a PdfStream.
  bool isStream() => getObjectType() == PdfObjectType.stream;

  /// Checks if this is a PdfIndirectReference.
  bool isIndirectReference() =>
      getObjectType() == PdfObjectType.indirectReference;

  /// Checks if this is a PdfLiteral.
  bool isLiteral() => getObjectType() == PdfObjectType.literal;

  /// Sets the indirect reference.
  PdfObject setIndirectReference(PdfIndirectReference? ref) {
    indirectReference = ref;
    return this;
  }

  /// Makes the object indirect.
  PdfObject makeIndirect(PdfDocument document) {
    if (getIndirectReference() == null) {
      setIndirectReference(document.createNextIndirectReference());
      getIndirectReference()!.setRefersTo(this);
    }
    return this;
  }

  /// Creates new instance of object.
  PdfObject newInstance();

  /// Checks state of a flag.
  bool checkState(int state) {
    return (_state & state) == state;
  }

  /// Sets state flags.
  PdfObject setState(int state) {
    _state |= state;
    return this;
  }

  /// Clears state flags.
  PdfObject clearState(int state) {
    _state &= ~state;
    return this;
  }

  /// Copies content from another object.
  void copyContent(PdfObject from, [dynamic document]) {
    // Override in subclasses
  }
}

/// Represents an indirect reference to a PDF object.
///
/// An indirect reference is a pointer to an object stored elsewhere
/// in the PDF document.
class PdfIndirectReference extends PdfObject {
  /// Object number.
  final int objNr;

  /// Generation number (mutable for reuse).
  int _genNr;

  /// The object this reference points to.
  PdfObject? _refersTo;

  /// Offset in the file where the object is stored.
  int _offset = 0;

  /// Object stream number (0 if not in an object stream).
  int _objStreamNumber = 0;

  /// Index in the object stream.
  int _index = 0;

  /// State flags for the reference.
  int _refState = 0;

  /// PdfDocument object belongs to.
  PdfDocument? _pdfDocument;

  /// PdfReader that created this reference.
  PdfReader? _reader;

  /// Creates a new indirect reference.
  PdfIndirectReference(this.objNr, [int genNr = 0, this._refersTo])
      : _genNr = genNr;

  PdfDocument? getDocument() => _pdfDocument;

  void setDocument(PdfDocument? doc) {
    _pdfDocument = doc;
  }

  PdfReader? getReader() => _reader;

  void setReader(PdfReader? reader) {
    _reader = reader;
  }

  @override
  int getObjectType() => PdfObjectType.indirectReference;

  @override
  PdfObject clone() {
    return PdfIndirectReference(objNr, _genNr, _refersTo);
  }

  @override
  PdfObject newInstance() {
    return PdfIndirectReference(objNr, _genNr);
  }

  /// Gets the object this reference points to.
  Future<PdfObject?> getRefersTo([bool allowFlushed = false]) async {
    if (_refersTo == null) {
      if (_pdfDocument != null) {
        _refersTo = await _pdfDocument!.readObject(this);
      } else if (_reader != null) {
        _refersTo = await _reader!.readObject(objNr);
      }
    }
    if (allowFlushed || !checkState(PdfObject.flushed)) {
      return _refersTo;
    }
    return null;
  }

  /// Sets the object this reference points to.
  void setRefersTo(PdfObject? obj) {
    _refersTo = obj;
  }

  /// Checks if the reference is free.
  bool isFree() {
    return checkState(PdfObject.free);
  }

  /// Gets the object number.
  int getObjNumber() => objNr;

  /// Gets the generation number.
  int getGenNumber() => _genNr;

  /// Increments the generation number.
  void incrementGenNumber() {
    _genNr++;
  }

  /// Gets the offset in the file.
  int getOffset() => _offset;

  /// Sets the offset in the file.
  void setOffset(int offset) {
    _offset = offset;
  }

  /// Gets the object stream number.
  int getObjStreamNumber() => _objStreamNumber;

  /// Sets the object stream number.
  void setObjStreamNumber(int objStreamNumber) {
    _objStreamNumber = objStreamNumber;
  }

  /// Gets the index in the object stream.
  int getIndex() => _index;

  /// Sets the index in the object stream.
  void setIndex(int index) {
    _index = index;
  }

  @override
  bool checkState(int state) {
    return (_refState & state) == state;
  }

  @override
  PdfObject setState(int state) {
    _refState |= state;
    return this;
  }

  @override
  PdfObject clearState(int state) {
    _refState &= ~state;
    return this;
  }

  @override
  String toString() {
    return '$objNr $_genNr R';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfIndirectReference) return false;
    return objNr == other.objNr && _genNr == other._genNr;
  }

  @override
  int get hashCode => Object.hash(objNr, _genNr);
}

/// State enum for object state flags (convenience).
class PdfObjectState {
  PdfObjectState._();

  static const int flushed = PdfObject.flushed;
  static const int free = PdfObject.free;
  static const int reading = PdfObject.reading;
  static const int modified = PdfObject.modified;
  static const int originalObjectStream = PdfObject.originalObjectStream;
  static const int mustBeFlushed = PdfObject.mustBeFlushed;
  static const int mustBeIndirect = PdfObject.mustBeIndirect;
  static const int forbidRelease = PdfObject.forbidRelease;
  static const int readOnly = PdfObject.readOnly;
  static const int unencrypted = PdfObject.unencrypted;
}
