import 'pdf_object.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_string.dart';
import 'pdf_boolean.dart';
import 'pdf_dictionary.dart';

/// A representation of an array as described in the PDF specification.
///
/// A PdfArray can contain any subclass of [PdfObject].
class PdfArray extends PdfObject {
  /// The internal list of objects.
  List<PdfObject>? _list;

  /// Create a new, empty PdfArray.
  PdfArray() {
    _list = <PdfObject>[];
  }

  /// Create a new PdfArray with the provided PdfObject as the first item.
  PdfArray.withObject(PdfObject obj) {
    _list = <PdfObject>[obj];
  }

  /// Create a new PdfArray from another PdfArray.
  PdfArray.fromArray(PdfArray arr) {
    _list = List<PdfObject>.from(arr._list ?? []);
  }

  /// Create a new PdfArray from a list of PdfObjects.
  PdfArray.fromList(List<PdfObject> objects) {
    _list = List<PdfObject>.from(objects);
  }

  /// Create a new PdfArray from a list of doubles.
  PdfArray.fromDoubles(List<double> numbers) {
    _list = numbers.map((n) => PdfNumber(n)).toList();
  }

  /// Create a new PdfArray from a list of ints.
  PdfArray.fromInts(List<int> numbers) {
    _list = numbers.map((n) => PdfNumber.fromInt(n)).toList();
  }

  /// Create a new PdfArray from a list of booleans.
  PdfArray.fromBooleans(List<bool> values) {
    _list = values.map((b) => PdfBoolean(b)).toList();
  }

  /// Create a new PdfArray from a list of strings.
  ///
  /// [asNames] if true, strings are added as PdfName, otherwise as PdfString.
  PdfArray.fromStrings(List<String> strings, {bool asNames = false}) {
    _list = strings
        .map((s) => asNames ? PdfName(s) as PdfObject : PdfString(s))
        .toList();
  }

  @override
  int getObjectType() => PdfObjectType.array;

  @override
  PdfObject clone() {
    final cloned = PdfArray();
    if (_list != null) {
      for (final obj in _list!) {
        cloned.add(obj.clone());
      }
    }
    return cloned;
  }

  @override
  PdfObject newInstance() {
    return PdfArray();
  }

  /// Gets the size of the array.
  int size() => _list?.length ?? 0;

  /// Gets the length of the array.
  int get length => size();

  /// Checks whether the array is empty.
  bool get isEmptyArray => _list?.isEmpty ?? true;

  /// Checks whether the array contains the passed object.
  bool containsObject(PdfObject o) {
    if (_list == null) return false;
    if (_list!.contains(o)) return true;
    for (final pdfObject in _list!) {
      if (_equalContent(o, pdfObject)) {
        return true;
      }
    }
    return false;
  }

  /// Returns an iterator over the array elements.
  Iterator<PdfObject> get iterator => _PdfArrayDirectIterator(_list ?? []);

  /// Adds the passed PdfObject to the array.
  void add(PdfObject pdfObject) {
    _list?.add(pdfObject);
  }

  /// Adds the specified PdfObject at the specified index.
  void insert(int index, PdfObject element) {
    _list?.insert(index, element);
  }

  /// Sets the PdfObject at the specified index.
  PdfObject? set(int index, PdfObject element) {
    if (_list == null || index >= _list!.length) return null;
    final old = _list![index];
    _list![index] = element;
    return old;
  }

  /// Adds all PdfObjects from a collection.
  void addAll(Iterable<PdfObject> c) {
    _list?.addAll(c);
  }

  /// Adds all PdfObjects from another PdfArray.
  void addAllFromArray(PdfArray a) {
    if (a._list != null) {
      addAll(a._list!);
    }
  }

  /// Gets the (direct) PdfObject at the specified index.
  PdfObject? get(int index, [bool asDirect = true]) {
    if (_list == null || index >= _list!.length) return null;
    if (!asDirect) {
      return _list![index];
    }
    final obj = _list![index];
    if (obj.getObjectType() == PdfObjectType.indirectReference) {
      return (obj as PdfIndirectReference).getRefersTo(true);
    }
    return obj;
  }

  /// Operator to get element at index.
  PdfObject? operator [](int index) => get(index);

  /// Operator to set element at index.
  void operator []=(int index, PdfObject value) => set(index, value);

  /// Removes the PdfObject at the specified index.
  void removeAt(int index) {
    _list?.removeAt(index);
  }

  /// Removes the first occurrence of the specified PdfObject.
  void remove(PdfObject o) {
    if (_list == null) return;
    if (_list!.remove(o)) return;
    for (var i = 0; i < _list!.length; i++) {
      if (_equalContent(o, _list![i])) {
        _list!.removeAt(i);
        return;
      }
    }
  }

  /// Remove all elements from the array.
  void clear() {
    _list?.clear();
  }

  /// Gets the first index of the specified PdfObject.
  int indexOf(PdfObject o) {
    if (_list == null) return -1;
    var index = 0;
    for (final pdfObject in _list!) {
      if (_equalContent(o, pdfObject)) {
        return index;
      }
      index++;
    }
    return -1;
  }

  /// Returns a sublist of this PdfArray.
  List<PdfObject> subList(int fromIndex, int toIndex) {
    return _list?.sublist(fromIndex, toIndex) ?? [];
  }

  /// Returns an unmodifiable list representation.
  List<PdfObject> toListCopy({bool growable = true}) {
    if (!growable) {
      return List.unmodifiable(_list ?? []);
    }
    return List<PdfObject>.from(_list ?? []);
  }

  /// Returns the element at the specified index as a PdfArray.
  PdfArray? getAsArray(int index) {
    final direct = get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.array) {
      return direct as PdfArray;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfDictionary.
  PdfDictionary? getAsDictionary(int index) {
    final direct = get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.dictionary) {
      return direct as PdfDictionary;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfNumber.
  PdfNumber? getAsNumber(int index) {
    final direct = get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.number) {
      return direct as PdfNumber;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfName.
  PdfName? getAsName(int index) {
    final direct = get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.name) {
      return direct as PdfName;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfString.
  PdfString? getAsString(int index) {
    final direct = get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.string) {
      return direct as PdfString;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfBoolean.
  PdfBoolean? getAsBoolean(int index) {
    final direct = get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.boolean) {
      return direct as PdfBoolean;
    }
    return null;
  }

  /// Returns this array as an array of doubles.
  List<double> toDoubleArray() {
    final result = <double>[];
    for (var k = 0; k < size(); k++) {
      final num = getAsNumber(k);
      if (num != null) {
        result.add(num.doubleValue());
      }
    }
    return result;
  }

  /// Returns this array as an array of ints.
  List<int> toIntArray() {
    final result = <int>[];
    for (var k = 0; k < size(); k++) {
      final num = getAsNumber(k);
      if (num != null) {
        result.add(num.intValue());
      }
    }
    return result;
  }

  /// Returns this array as an array of booleans.
  List<bool> toBooleanArray() {
    final result = <bool>[];
    for (var k = 0; k < size(); k++) {
      final b = getAsBoolean(k);
      if (b != null) {
        result.add(b.getValue());
      }
    }
    return result;
  }

  /// Releases the content.
  void releaseContent() {
    _list = null;
  }

  /// Helper to compare PDF object content.
  static bool _equalContent(PdfObject? obj1, PdfObject? obj2) {
    if (obj1 == null || obj2 == null) return obj1 == obj2;
    PdfObject? direct1 = obj1;
    PdfObject? direct2 = obj2;
    if (obj1.isIndirectReference()) {
      direct1 = (obj1 as PdfIndirectReference).getRefersTo(true);
    }
    if (obj2.isIndirectReference()) {
      direct2 = (obj2 as PdfIndirectReference).getRefersTo(true);
    }
    return direct1 == direct2;
  }

  @override
  String toString() {
    final buffer = StringBuffer('[');
    if (_list != null) {
      for (final entry in _list!) {
        final ref = entry.getIndirectReference();
        buffer.write(ref?.toString() ?? entry.toString());
        buffer.write(' ');
      }
    }
    buffer.write(']');
    return buffer.toString();
  }
}

/// Iterator that returns direct objects.
class _PdfArrayDirectIterator implements Iterator<PdfObject> {
  final List<PdfObject> _list;
  int _index = -1;

  _PdfArrayDirectIterator(this._list);

  @override
  PdfObject get current {
    final obj = _list[_index];
    if (obj.getObjectType() == PdfObjectType.indirectReference) {
      return (obj as PdfIndirectReference).getRefersTo(true) ?? obj;
    }
    return obj;
  }

  @override
  bool moveNext() {
    _index++;
    return _index < _list.length;
  }
}
