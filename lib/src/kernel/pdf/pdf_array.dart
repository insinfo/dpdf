import 'package:pdfcraft/src/kernel/geom/rectangle.dart';
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
class CraftPdfArray extends CraftPdfObject {
  /// The internal list of objects.
  List<CraftPdfObject>? _list;

  /// Create a new, empty PdfArray.
  CraftPdfArray() {
    _list = <CraftPdfObject>[];
  }

  /// Create a new PdfArray with the provided PdfObject as the first item.
  CraftPdfArray.withObject(CraftPdfObject obj) {
    _list = <CraftPdfObject>[obj];
  }

  /// Create a new PdfArray from another PdfArray.
  CraftPdfArray.fromArray(CraftPdfArray arr) {
    _list = List<CraftPdfObject>.from(arr._list ?? []);
  }

  /// Create a new PdfArray from a list of PdfObjects.
  CraftPdfArray.fromList(List<CraftPdfObject> objects) {
    _list = List<CraftPdfObject>.from(objects);
  }

  /// Create a new PdfArray from a list of doubles.
  CraftPdfArray.fromDoubles(List<double> numbers) {
    _list = numbers.map((n) => CraftPdfNumber(n)).toList();
  }

  /// Create a new PdfArray from a list of ints.
  CraftPdfArray.fromInts(List<int> numbers) {
    _list = numbers.map((n) => CraftPdfNumber.fromInt(n)).toList();
  }

  /// Create a new PdfArray from a list of booleans.
  CraftPdfArray.fromBooleans(List<bool> values) {
    _list = values.map((b) => CraftPdfBoolean(b)).toList();
  }

  /// Create a new PdfArray from a list of strings.
  ///
  /// [asNames] if true, strings are added as PdfName, otherwise as PdfString.
  CraftPdfArray.fromStrings(List<String> strings, {bool asNames = false}) {
    _list = strings
        .map((s) =>
            asNames ? CraftPdfName(s) as CraftPdfObject : CraftPdfString(s))
        .toList();
  }

  /// Create a new PdfArray from a Rectangle.
  CraftPdfArray.fromRectangle(CraftRectangle rect) {
    _list = [
      CraftPdfNumber(rect.getX()),
      CraftPdfNumber(rect.getY()),
      CraftPdfNumber(rect.getX() + rect.getWidth()),
      CraftPdfNumber(rect.getY() + rect.getHeight())
    ];
  }

  @override
  int objectKind() => PdfObjectType.array;

  @override
  CraftPdfObject clone() {
    final cloned = CraftPdfArray();
    if (_list != null) {
      for (final obj in _list!) {
        if (obj.indirectHandle() != null) {
          cloned.add(obj.indirectHandle()!);
        } else {
          cloned.add(obj.clone());
        }
      }
    }
    return cloned;
  }

  @override
  CraftPdfObject newInstance() {
    return CraftPdfArray();
  }

  /// Gets the size of the array.
  int size() => _list?.length ?? 0;

  /// Gets the length of the array.
  int get length => size();

  /// Checks whether the array is empty.
  bool get isEmptyArray => _list?.isEmpty ?? true;

  /// Checks whether the array is empty.
  bool isEmpty() => _list?.isEmpty ?? true;

  /// Checks whether the array contains the passed object.
  Future<bool> containsObject(CraftPdfObject o) async {
    if (_list == null) return false;
    for (final pdfObject in _list!) {
      if (await _equalContent(o, pdfObject)) {
        return true;
      }
    }
    return false;
  }

  /// Adds the passed PdfObject to the array.
  void add(CraftPdfObject pdfObject) {
    _list?.add(pdfObject);
  }

  /// Adds the specified PdfObject at the specified index.
  void insert(int index, CraftPdfObject element) {
    _list?.insert(index, element);
  }

  /// Sets the PdfObject at the specified index.
  CraftPdfObject? set(int index, CraftPdfObject element) {
    if (_list == null || index >= _list!.length) return null;
    final old = _list![index];
    _list![index] = element;
    return old;
  }

  /// Adds all PdfObjects from a collection.
  void addAll(Iterable<CraftPdfObject> c) {
    _list?.addAll(c);
  }

  /// Adds all PdfObjects from another PdfArray.
  void addAllFromArray(CraftPdfArray a) {
    if (a._list != null) {
      addAll(a._list!);
    }
  }

  /// Gets the (direct) PdfObject at the specified index.
  Future<CraftPdfObject?> get(int index, [bool asDirect = true]) async {
    if (_list == null || index >= _list!.length) return null;
    final obj = _list![index];
    if (asDirect && obj.objectKind() == PdfObjectType.indirectReference) {
      return await (obj as CraftPdfIndirectReference).targetObject(true);
    }
    return obj;
  }

  /// Removes the PdfObject at the specified index.
  void removeAt(int index) {
    _list?.removeAt(index);
  }

  /// Removes the first occurrence of the specified PdfObject.
  Future<void> remove(CraftPdfObject o) async {
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
  Future<int> indexOf(CraftPdfObject o) async {
    if (_list == null) return -1;
    for (var i = 0; i < _list!.length; i++) {
      if (await _equalContent(o, _list![i])) {
        return i;
      }
    }
    return -1;
  }

  /// Returns a sublist of this PdfArray.
  List<CraftPdfObject> subList(int fromIndex, int toIndex) {
    return _list?.sublist(fromIndex, toIndex) ?? [];
  }

  /// Returns a list copy of the array elements.
  List<CraftPdfObject> toListCopy({bool growable = true}) {
    if (!growable) {
      return List.unmodifiable(_list ?? []);
    }
    return List<CraftPdfObject>.from(_list ?? []);
  }

  /// Returns a list of the array elements (alias for toListCopy).
  List<CraftPdfObject> toList() {
    return List<CraftPdfObject>.from(_list ?? []);
  }

  /// Returns the element at the specified index as a PdfArray.
  Future<CraftPdfArray?> arrayEntry(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.objectKind() == PdfObjectType.array) {
      return direct as CraftPdfArray;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfDictionary.
  Future<CraftPdfDictionary?> dictionaryEntry(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.objectKind() == PdfObjectType.dictionary) {
      return direct as CraftPdfDictionary;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfNumber.
  Future<CraftPdfNumber?> numberEntry(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.objectKind() == PdfObjectType.number) {
      return direct as CraftPdfNumber;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfName.
  Future<CraftPdfName?> nameEntry(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.objectKind() == PdfObjectType.name) {
      return direct as CraftPdfName;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfString.
  Future<CraftPdfString?> stringEntry(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.objectKind() == PdfObjectType.string) {
      return direct as CraftPdfString;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfBoolean.
  Future<CraftPdfBoolean?> booleanEntry(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.objectKind() == PdfObjectType.boolean) {
      return direct as CraftPdfBoolean;
    }
    return null;
  }

  /// Returns the element at the specified index as a PdfStream.
  Future<CraftPdfStream?> streamEntry(int index) async {
    final direct = await get(index, true);
    if (direct != null && direct.objectKind() == PdfObjectType.stream) {
      return direct as CraftPdfStream;
    }
    return null;
  }

  /// Returns this array as an array of doubles.
  Future<List<double>> toDoubleArray() async {
    final result = <double>[];
    for (var k = 0; k < size(); k++) {
      final num = await numberEntry(k);
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
      final num = await numberEntry(k);
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
      final b = await booleanEntry(k);
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
  static Future<bool> _equalContent(
      CraftPdfObject? obj1, CraftPdfObject? obj2) async {
    if (obj1 == null || obj2 == null) return obj1 == obj2;
    CraftPdfObject? direct1 = obj1;
    CraftPdfObject? direct2 = obj2;
    if (obj1.isIndirectReference()) {
      direct1 = await (obj1 as CraftPdfIndirectReference).targetObject(true);
    }
    if (obj2.isIndirectReference()) {
      direct2 = await (obj2 as CraftPdfIndirectReference).targetObject(true);
    }
    return direct1 == direct2;
  }

  @override
  String toString() {
    final buffer = StringBuffer('[');
    if (_list != null) {
      for (final entry in _list!) {
        final ref = entry.indirectHandle();
        buffer.write(ref?.toString() ?? entry.toString());
        buffer.write(' ');
      }
    }
    buffer.write(']');
    return buffer.toString();
  }
}
