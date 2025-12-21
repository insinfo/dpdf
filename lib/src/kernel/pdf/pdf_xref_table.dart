import 'pdf_object.dart';

/// A representation of a cross-reference table of a PDF document.
///
/// The xref table maps object numbers to their byte offsets in the PDF file,
/// enabling random access to any object in the document.
class PdfXrefTable {
  /// Maximum generation number for a PDF object.
  static const int maxGeneration = 65535;

  /// Initial capacity of the xref array.
  static const int _initialCapacity = 32;

  /// Array of indirect references indexed by object number.
  List<PdfIndirectReference?> _xref;

  /// Count of objects (highest object number seen).
  int _count = 0;

  /// Whether reading of the document has been completed.
  bool _readingCompleted = false;

  /// Creates a new PdfXrefTable with default capacity.
  PdfXrefTable() : this.withCapacity(_initialCapacity);

  /// Creates a new PdfXrefTable with specified initial capacity.
  PdfXrefTable.withCapacity(int capacity)
      : _xref = List<PdfIndirectReference?>.filled(
            capacity < 1 ? _initialCapacity : capacity, null) {
    // Object 0 is always free with generation 65535
    add(PdfIndirectReference(0, maxGeneration)
      ..setOffset(0)
      ..setState(PdfObjectState.free));
  }

  /// Adds an indirect reference to the xref table.
  ///
  /// Returns the reference that was added.
  PdfIndirectReference? add(PdfIndirectReference? reference) {
    if (reference == null) {
      return null;
    }
    final objNr = reference.getObjNumber();
    _count = _count > objNr ? _count : objNr;
    _ensureCount(objNr);
    _xref[objNr] = reference;
    return reference;
  }

  /// Gets the size of the cross-reference table.
  ///
  /// Returns the number of entries including object 0.
  int size() => _count + 1;

  /// Gets the indirect reference for the specified object number.
  ///
  /// Returns null if the object number is out of range or not defined.
  PdfIndirectReference? get(int index) {
    if (index > _count || index < 0) {
      return null;
    }
    return _xref[index];
  }

  /// Checks if there is a reference at the given index.
  bool containsKey(int index) {
    if (index > _count || index < 0) {
      return false;
    }
    return _xref[index] != null;
  }

  /// Sets whether reading of the document has been completed.
  void markReadingCompleted() {
    _readingCompleted = true;
  }

  /// Unmarks reading completion (for append mode).
  void unmarkReadingCompleted() {
    _readingCompleted = false;
  }

  /// Checks if reading of the document was completed.
  bool isReadingCompleted() => _readingCompleted;

  /// Gets the capacity of the xref table.
  int getCapacity() => _xref.length;

  /// Sets the capacity of the xref table.
  ///
  /// If [capacity] is larger than current capacity, extends the array.
  void setCapacity(int capacity) {
    if (capacity > _xref.length) {
      _extendXref(capacity);
    }
  }

  /// Calculates the number of stored references to indirect objects.
  int getCountOfIndirectObjects() {
    var countOfIndirectObjects = 0;
    for (final ref in _xref) {
      if (ref != null && !ref.isFree()) {
        countOfIndirectObjects++;
      }
    }
    return countOfIndirectObjects;
  }

  /// Sets the reference to free state.
  void freeReference(PdfIndirectReference reference) {
    if (reference.isFree()) {
      return;
    }
    reference
      ..setState(PdfObjectState.free)
      ..setState(PdfObjectState.modified);
    if (reference.getGenNumber() < maxGeneration) {
      reference.incrementGenNumber();
    }
  }

  /// Clears all references except object 0.
  void clear() {
    for (var i = 1; i <= _count; i++) {
      if (_xref[i] != null && _xref[i]!.isFree()) {
        continue;
      }
      _xref[i] = null;
    }
    _count = 1;
  }

  /// Clears all references including free references.
  void clearAllReferences() {
    for (var i = 1; i <= _count; i++) {
      _xref[i] = null;
    }
    _count = 1;
  }

  /// Ensures the array can hold at least [count] elements.
  void _ensureCount(int count) {
    if (count >= _xref.length) {
      _extendXref(count << 1);
    }
  }

  /// Extends the xref array to the specified capacity.
  void _extendXref(int capacity) {
    final newXref = List<PdfIndirectReference?>.filled(capacity, null);
    for (var i = 0; i < _xref.length; i++) {
      newXref[i] = _xref[i];
    }
    _xref = newXref;
  }

  /// Creates an iterator over all non-null references.
  Iterable<PdfIndirectReference> get references sync* {
    for (var i = 0; i <= _count; i++) {
      final ref = _xref[i];
      if (ref != null) {
        yield ref;
      }
    }
  }

  @override
  String toString() {
    return 'PdfXrefTable(size: ${size()}, objects: ${getCountOfIndirectObjects()})';
  }
}
