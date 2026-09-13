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
    final objNr = reference.objectNumber();
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
    if (reference.generationNumber() < maxGeneration) {
      reference.incrementGenNumber();
    }
  }

  /// Clears all references except object 0.
  void clear() {
    var highestRetained = 0;
    for (var i = 1; i <= _count; i++) {
      if (_xref[i] != null && _xref[i]!.isFree()) {
        highestRetained = i;
        continue;
      }
      _xref[i] = null;
    }
    _count = highestRetained;
  }

  /// Clears all references including free references.
  void clearAllReferences() {
    for (var i = 1; i <= _count; i++) {
      _xref[i] = null;
    }
    _count = 0;
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

  /// Rebuilds the linked list of free entries required by 7.5.4.
  ///
  /// A cross-reference table's free entries form a chain: the second field of
  /// a free entry is the object number of the next free object, and the last
  /// link is 0. The head of the chain is the mandatory entry for object 0,
  /// whose generation number is 65535. Before this ran, every free entry was
  /// written with a next-object field of 0, which makes the chain claim there
  /// are no further free objects and leaves a conforming reader unable to
  /// reuse any of those numbers.
  ///
  /// Object numbers with no reference at all are free as well (7.5.4 requires
  /// an entry for every number below /Size), so they join the chain and get a
  /// reference of their own with generation 65535 — the value 7.5.4 reserves
  /// for a number that shall not be reused.
  ///
  /// [document] is accepted for call-site symmetry with the rest of the
  /// document lifecycle and is not otherwise consulted.
  void initFreeReferencesList(dynamic document) {
    final head = _xref[0];
    if (head == null) {
      add(PdfIndirectReference(0, maxGeneration)
        ..setOffset(0)
        ..setState(PdfObjectState.free));
    } else if (!head.isFree()) {
      head.setState(PdfObjectState.free);
    }

    final freeNumbers = <int>[];
    for (var i = 1; i <= _count; i++) {
      final reference = _xref[i];
      if (reference == null) {
        _xref[i] = PdfIndirectReference(i, maxGeneration)
          ..setOffset(0)
          ..setState(PdfObjectState.free);
        freeNumbers.add(i);
      } else if (reference.isFree()) {
        freeNumbers.add(i);
      }
    }

    var previous = _xref[0]!;
    for (final number in freeNumbers) {
      previous.setOffset(number);
      previous = _xref[number]!;
    }
    // The chain ends by pointing back at object 0.
    previous.setOffset(0);
  }

  /// The object numbers of the free entries, in chain order (7.5.4).
  ///
  /// The head entry for object 0 is not included; the list is what a writer
  /// needs to emit the free entries of a table or of a cross-reference stream.
  List<int> freeReferencesChain() {
    final chain = <int>[];
    final visited = <int>{};
    var current = _xref[0];
    while (current != null) {
      final next = current.getOffset();
      if (next <= 0 || next > _count || !visited.add(next)) break;
      final reference = _xref[next];
      if (reference == null || !reference.isFree()) break;
      chain.add(next);
      current = reference;
    }
    return chain;
  }

  @override
  String toString() {
    return 'PdfXrefTable(size: ${size()}, objects: ${getCountOfIndirectObjects()})';
  }
}
