import 'pdf_document.dart';
import 'pdf_reader.dart';
import 'pdf_object_copier.dart';

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
abstract class CraftPdfObject {
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

  /// Retains the indirect handle after the object is written.
  CraftPdfIndirectReference? indirectReference;

  /// State flags for this object.
  int _state = 0;

  /// Offset in the file where the object was written.
  int _offset = 0;

  /// Gets object type.
  int objectKind();

  /// Gets the offset in the file.
  int getOffset() => _offset;

  /// Sets the offset in the file.
  void setOffset(int offset) {
    _offset = offset;
  }

  /// Flushes the object to the document.
  Future<void> flush([bool canBeInObjStm = true]) async {
    if (hasBeenWritten() || indirectHandle() == null) {
      return;
    }
    final doc = indirectHandle()!.getDocument();
    if (doc != null && !doc.lifecycleClosed()) {
      final writer = doc.outputWriter();
      if (writer != null) {
        await writer.writeObject(this, canBeInObjStm: canBeInObjStm);
      }
    }
  }

  /// Gets the indirect reference associated with the object.
  CraftPdfIndirectReference? indirectHandle() {
    return indirectReference;
  }

  /// Checks if object is indirect.
  bool usesIndirectStorage() {
    return indirectReference != null || checkState(mustBeIndirect);
  }

  /// Indicates if the object has been flushed.
  bool hasBeenWritten() {
    final ref = indirectHandle();
    return ref != null && ref.checkState(flushed);
  }

  /// Indicates if the object has been modified.
  bool hasChanges() {
    final ref = indirectHandle();
    return ref != null && ref.checkState(modified);
  }

  /// Creates a clone of the object.
  CraftPdfObject clone();

  /// Deep-copies this object graph into a writable destination document.
  /// Use PdfObjectCopier directly to share mappings across multiple roots.
  Future<CraftPdfObject> copyTo(CraftPdfDocument document) =>
      PdfObjectCopier(document).copy(this);

  /// Sets the modified flag.
  CraftPdfObject markChanged() {
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
  bool isNull() => objectKind() == PdfObjectType.nullType;

  /// Checks if this is a PdfBoolean.
  bool isBoolean() => objectKind() == PdfObjectType.boolean;

  /// Checks if this is a PdfNumber.
  bool isNumber() => objectKind() == PdfObjectType.number;

  /// Checks if this is a PdfString.
  bool isString() => objectKind() == PdfObjectType.string;

  /// Checks if this is a PdfName.
  bool isName() => objectKind() == PdfObjectType.name;

  /// Checks if this is a PdfArray.
  bool isArray() => objectKind() == PdfObjectType.array;

  /// Checks if this is a PdfDictionary.
  bool isDictionary() => objectKind() == PdfObjectType.dictionary;

  /// Checks if this is a PdfStream.
  bool isStream() => objectKind() == PdfObjectType.stream;

  /// Checks if this is a PdfIndirectReference.
  bool isIndirectReference() => objectKind() == PdfObjectType.indirectReference;

  /// Checks if this is a PdfLiteral.
  bool isLiteral() => objectKind() == PdfObjectType.literal;

  /// Sets the indirect reference.
  CraftPdfObject setIndirectReference(CraftPdfIndirectReference? ref) {
    indirectReference = ref;
    return this;
  }

  /// Makes the object indirect.
  CraftPdfObject attachToDocument(CraftPdfDocument document) {
    if (indirectHandle() == null) {
      setIndirectReference(document.allocateObjectHandle());
      indirectHandle()!.assignTargetObject(this);
    }
    return this;
  }

  /// Creates new instance of object.
  CraftPdfObject newInstance();

  /// Checks state of a flag.
  bool checkState(int state) {
    return (_state & state) == state;
  }

  /// Sets state flags.
  CraftPdfObject setState(int state) {
    _state |= state;
    return this;
  }

  /// Clears state flags.
  CraftPdfObject clearState(int state) {
    _state &= ~state;
    return this;
  }

  /// Copies content from another object.
  void copyContent(CraftPdfObject from, [dynamic document]) {
    // Override in subclasses
  }
}

/// Represents an indirect reference to a PDF object.
///
/// An indirect reference is a pointer to an object stored elsewhere
/// in the PDF document.
class CraftPdfIndirectReference extends CraftPdfObject {
  /// Object number.
  final int objNr;

  /// Generation number (mutable for reuse).
  int _genNr;

  /// The object this reference points to.
  CraftPdfObject? _refersTo;

  /// Offset in the file where the object is stored.
  int _offset = 0;

  /// Object stream number (0 if not in an object stream).
  int _objStreamNumber = 0;

  /// Index in the object stream.
  int _index = 0;

  /// State flags for the reference.
  int _refState = 0;

  /// PdfDocument object belongs to.
  CraftPdfDocument? _pdfDocument;

  /// PdfReader that created this reference.
  CraftPdfReader? _reader;

  /// Creates a new indirect reference.
  CraftPdfIndirectReference(this.objNr, [int genNr = 0, this._refersTo])
      : _genNr = genNr;

  CraftPdfDocument? getDocument() => _pdfDocument;

  void setDocument(CraftPdfDocument? doc) {
    _pdfDocument = doc;
  }

  CraftPdfReader? inputReader() => _reader;

  void setReader(CraftPdfReader? reader) {
    _reader = reader;
  }

  @override
  int objectKind() => PdfObjectType.indirectReference;

  @override
  CraftPdfObject clone() {
    return CraftPdfIndirectReference(objNr, _genNr, _refersTo);
  }

  @override
  CraftPdfObject newInstance() {
    return CraftPdfIndirectReference(objNr, _genNr);
  }

  /// Gets the object this reference points to.
  Future<CraftPdfObject?> targetObject([bool allowFlushed = false]) async {
    if (_refersTo == null) {
      if (_pdfDocument != null) {
        _refersTo = await _pdfDocument!.readObject(this);
      } else if (_reader != null) {
        _refersTo = await _reader!.readObject(objNr);
      }
    }

    if (_refersTo != null && _refersTo!.indirectHandle() == null) {
      _refersTo!.setIndirectReference(this);
    }

    if (allowFlushed || !checkState(CraftPdfObject.flushed)) {
      return _refersTo;
    }
    return null;
  }

  /// Gets the object this reference points to synchronously.
  /// If object is not loaded, it might return null.
  CraftPdfObject? targetObjectSync() {
    return _refersTo;
  }

  /// Sets the object this reference points to.
  void assignTargetObject(CraftPdfObject? obj) {
    _refersTo = obj;
  }

  /// Checks if the reference is free.
  bool isFree() {
    return checkState(CraftPdfObject.free);
  }

  /// Checks if the reference/object has been modified.
  /// Used in append mode to determine which objects need to be written.
  @override
  bool hasChanges() {
    return checkState(CraftPdfObject.modified);
  }

  /// Marks this reference as modified.
  /// Used in append mode for incremental updates.
  CraftPdfIndirectReference markAsModified() {
    setState(CraftPdfObject.modified);
    return this;
  }

  /// Gets the object number.
  int objectNumber() => objNr;

  /// Gets the generation number.
  int generationNumber() => _genNr;

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
  CraftPdfObject setState(int state) {
    _refState |= state;
    return this;
  }

  @override
  CraftPdfObject clearState(int state) {
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
    if (other is! CraftPdfIndirectReference) return false;
    return objNr == other.objNr && _genNr == other._genNr;
  }

  @override
  int get hashCode => Object.hash(objNr, _genNr);
}

/// State enum for object state flags (convenience).
class PdfObjectState {
  PdfObjectState._();

  static const int flushed = CraftPdfObject.flushed;
  static const int free = CraftPdfObject.free;
  static const int reading = CraftPdfObject.reading;
  static const int modified = CraftPdfObject.modified;
  static const int originalObjectStream = CraftPdfObject.originalObjectStream;
  static const int mustBeFlushed = CraftPdfObject.mustBeFlushed;
  static const int mustBeIndirect = CraftPdfObject.mustBeIndirect;
  static const int forbidRelease = CraftPdfObject.forbidRelease;
  static const int readOnly = CraftPdfObject.readOnly;
  static const int unencrypted = CraftPdfObject.unencrypted;
}
