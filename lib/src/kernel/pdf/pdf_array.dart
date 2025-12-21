import 'pdf_object.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_string.dart';
import 'pdf_boolean.dart';
import 'pdf_dictionary.dart';
import 'pdf_stream.dart';

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
  Future<bool> containsObject(PdfObject o) async {
    if (_list == null) return false;
    for (final pdfObject in _list!) {
      if (await _equalContent(o, pdfObject)) {
        return true;
      }
    }
    return false;
  }

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
  Future<PdfObject?> get(int index, [bool asDirect = true]) async {
    if (_list == null || index >= _list!.length) return null;
    final obj = _list![index];
    if (asDirect && obj.getObjectType() == PdfObjectType.indirectReference) {
      return await (obj as PdfIndirectReference).getRefersTo(true);
    }
    return obj;
  }

  /// Removes the PdfObject at the specified index.
  void removeAt(int index) {
    _list?.removeAt(index);
  }

  /// Removes the first occurrence of the specified PdfObject.
  Future<void> remove(PdfObject o) async {
    if (_list == null) return;
    for (var i = 0; i < _list!.length; i++) {
      if (await _equalContent(o, _list![i])) {
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
  Future<int> indexOf(PdfObject o) async {
    if (_list == null) return -1;
    for (var i = 0; i < _list!.length; i++) {
      if (await _equalContent(o, _list![i])) {
        return i;
      }
    }
    return -1;
  }

  /// Returns a sublist of this PdfArray.
  List<PdfObject> subList(int fromIndex, int toIndex) {
    return _list?.sublist(fromIndex, toIndex) ?? [];
  }

  /// Returns a list copy of the array elements.
  List<PdfObject> toListCopy({bool growable = true}) {
    if (!growable) {
      return List.unmodifiable(_list ?? []);
    }
    return List<PdfObject>.from(_list ?? []);
  }

  /// Returns a list of the array elements (alias for toListCopy).
  List<PdfObject> toList() {
    return List<PdfObject>.from(_list ?? []);
  }

  /// Returns the element at the specified index as a PdfArray.
  Future<PdfArray?> getAsArray(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.array) {
      return direct as PdfArray;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfDictionary.
  Future<PdfDictionary?> getAsDictionary(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.dictionary) {
      return direct as PdfDictionary;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfNumber.
  Future<PdfNumber?> getAsNumber(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.number) {
      return direct as PdfNumber;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfName.
  Future<PdfName?> getAsName(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.name) {
      return direct as PdfName;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfString.
  Future<PdfString?> getAsString(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.string) {
      return direct as PdfString;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfBoolean.
  Future<PdfBoolean?> getAsBoolean(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.boolean) {
      return direct as PdfBoolean;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfStream.
  Future<PdfStream?> getAsStream(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.stream) {
      return direct as PdfStream;
    }
    return null;
  }

  /// Returns this array as an array of doubles.
  Future<List<double>> toDoubleArray() async {
    final result = <double>[];
    for (var k = 0; k < size(); k++) {
      final num = await getAsNumber(k);
      if (num != null) {
        result.add(num.doubleValue());
      }
    }
    return result;
  }

  /// Returns this array as an array of ints.
  Future<List<int>> toIntArray() async {
    final result = <int>[];
    for (var k = 0; k < size(); k++) {
      final num = await getAsNumber(k);
      if (num != null) {
        result.add(num.intValue());
      }
    }
    return result;
  }

  /// Returns this array as an array of booleans.
  Future<List<bool>> toBooleanArray() async {
    final result = <bool>[];
    for (var k = 0; k < size(); k++) {
      final b = await getAsBoolean(k);
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
  static Future<bool> _equalContent(PdfObject? obj1, PdfObject? obj2) async {
    if (obj1 == null || obj2 == null) return obj1 == obj2;
    PdfObject? direct1 = obj1;
    PdfObject? direct2 = obj2;
    if (obj1.isIndirectReference()) {
      direct1 = await (obj1 as PdfIndirectReference).getRefersTo(true);
    }
    if (obj2.isIndirectReference()) {
      direct2 = await (obj2 as PdfIndirectReference).getRefersTo(true);
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
