import 'pdf_object.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_string.dart';
import 'pdf_boolean.dart';
import 'pdf_array.dart' show CraftPdfArray;
import 'pdf_stream.dart';

/// A representation of a Dictionary as described by the PDF Specification.
///
/// A Dictionary is a mapping between keys and values. Keys are [PdfName]s
/// and the values are [PdfObject]s. Each key can only be associated with
/// one value.
class CraftPdfDictionary extends CraftPdfObject {
  /// The internal map.
  Map<CraftPdfName, CraftPdfObject>? _map;

  /// Gets the internal map.
  Map<CraftPdfName, CraftPdfObject>? getMap() => _map;

  /// Creates a new PdfDictionary instance.
  CraftPdfDictionary() {
    _map = <CraftPdfName, CraftPdfObject>{};
  }

  /// Creates a new PdfDictionary from a map.
  CraftPdfDictionary.fromMap(Map<CraftPdfName, CraftPdfObject> map) {
    _map = Map<CraftPdfName, CraftPdfObject>.from(map);
  }

  /// Creates a new PdfDictionary from entries.
  CraftPdfDictionary.fromEntries(
      Iterable<MapEntry<CraftPdfName, CraftPdfObject>> entries) {
    _map = Map<CraftPdfName, CraftPdfObject>.fromEntries(entries);
  }

  /// Creates a new PdfDictionary from another PdfDictionary.
  CraftPdfDictionary.fromDictionary(CraftPdfDictionary dictionary) {
    _map = Map<CraftPdfName, CraftPdfObject>.from(dictionary._map ?? {});
  }

  @override
  int objectKind() => PdfObjectType.dictionary;

  @override
  CraftPdfObject clone() {
    final cloned = CraftPdfDictionary();
    if (_map != null) {
      for (final entry in _map!.entries) {
        final val = entry.value;
        if (val.indirectHandle() != null) {
          cloned.put(entry.key, val.indirectHandle()!);
        } else {
          cloned.put(entry.key, val.clone());
        }
      }
    }
    return cloned;
  }

  @override
  CraftPdfObject newInstance() {
    return CraftPdfDictionary();
  }

  /// Returns the number of key-value pairs.
  int size() => _map?.length ?? 0;

  /// Returns true if there are no key-value pairs.
  bool isEmpty() => _map?.isEmpty ?? true;

  /// Tests membership of a dictionary key.
  bool containsKey(CraftPdfName key) => _map?.containsKey(key) ?? false;

  /// Tests membership of a dictionary value.
  bool containsValue(CraftPdfObject value) =>
      _map?.containsValue(value) ?? false;

  /// Returns the value associated with this key.
  ///
  /// If [asDirect] is true and the value is an indirect reference,
  /// attempts to resolve it. If the reference cannot be resolved,
  /// returns the reference itself. By default the raw object (including
  /// indirect references) is returned to allow callers to decide when
  /// dereferencing is appropriate.
  Future<CraftPdfObject?> get(CraftPdfName key, [bool asDirect = false]) async {
    if (_map == null) return null;
    final obj = _map![key];
    if (asDirect &&
        obj != null &&
        obj.objectKind() == PdfObjectType.indirectReference) {
      final resolved =
          await (obj as CraftPdfIndirectReference).targetObject(true);
      // Return resolved object if available, otherwise the reference itself
      return resolved ?? obj;
    }
    return obj;
  }

  /// Returns the value as a PdfArray.
  Future<CraftPdfArray?> arrayEntry(CraftPdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.array) {
      return direct as CraftPdfArray;
    }
    return null;
  }

  /// Returns the value as a PdfDictionary.
  Future<CraftPdfDictionary?> dictionaryEntry(CraftPdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.dictionary) {
      return direct as CraftPdfDictionary;
    }
    return null;
  }

  /// Returns the value as a PdfStream.
  Future<CraftPdfStream?> streamEntry(CraftPdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.stream) {
      return direct as CraftPdfStream;
    }
    return null;
  }

  /// Returns the value as a PdfNumber.
  Future<CraftPdfNumber?> numberEntry(CraftPdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.number) {
      return direct as CraftPdfNumber;
    }
    return null;
  }

  /// Returns the value as a PdfNumber synchronously (does not resolve indirect references).
  CraftPdfNumber? getNumberSync(CraftPdfName key) {
    final obj = _map?[key];
    if (obj != null && obj.objectKind() == PdfObjectType.number) {
      return obj as CraftPdfNumber;
    }
    return null;
  }

  /// Returns the value as a PdfBoolean synchronously (does not resolve indirect references).
  CraftPdfBoolean? getBooleanSync(CraftPdfName key) {
    final obj = _map?[key];
    if (obj != null && obj.objectKind() == PdfObjectType.boolean) {
      return obj as CraftPdfBoolean;
    }
    return null;
  }

  /// Returns the value as a PdfName.
  Future<CraftPdfName?> nameEntry(CraftPdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.name) {
      return direct as CraftPdfName;
    }
    return null;
  }

  /// Returns the value as a PdfString.
  Future<CraftPdfString?> stringEntry(CraftPdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.string) {
      return direct as CraftPdfString;
    }
    return null;
  }

  /// Returns the value as a PdfBoolean.
  Future<CraftPdfBoolean?> booleanEntry(CraftPdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.boolean) {
      return direct as CraftPdfBoolean;
    }
    return null;
  }

  /// Returns the value as a double.
  Future<double?> decimalEntry(CraftPdfName key) async {
    final number = await numberEntry(key);
    return number?.doubleValue();
  }

  /// Returns the value as an int.
  Future<int?> integerEntry(CraftPdfName key) async {
    final number = await numberEntry(key);
    return number?.intValue();
  }

  /// Returns the value as a bool.
  Future<bool?> flagEntry(CraftPdfName key) async {
    final b = await booleanEntry(key);
    return b?.getValue();
  }

  /// Inserts the value with the specified key.
  CraftPdfObject? put(CraftPdfName key, CraftPdfObject value) {
    if (_map == null) return null;
    final old = _map![key];
    _map![key] = value;
    return old;
  }

  /// Removes the specified key.
  CraftPdfObject? remove(CraftPdfName key) {
    return _map?.remove(key);
  }

  /// Inserts all key-value pairs from another dictionary.
  void putAll(CraftPdfDictionary d) {
    if (d._map != null) {
      _map?.addAll(d._map!);
    }
  }

  /// Removes all key-value pairs.
  void clear() {
    _map?.clear();
  }

  /// Returns all the keys as a Set.
  Set<CraftPdfName> keySet() {
    return _map?.keys.toSet() ?? <CraftPdfName>{};
  }

  /// Returns all the values.
  Future<Iterable<CraftPdfObject>> values([bool asDirects = true]) async {
    if (_map == null) return [];
    if (!asDirects) {
      return _map!.values;
    }
    final result = <CraftPdfObject>[];
    for (final obj in _map!.values) {
      if (obj.objectKind() == PdfObjectType.indirectReference) {
        result.add(
            await (obj as CraftPdfIndirectReference).targetObject(true) ?? obj);
      } else {
        result.add(obj);
      }
    }
    return result;
  }

  /// Returns all entries.
  Future<Iterable<MapEntry<CraftPdfName, CraftPdfObject>>> entrySet() async {
    if (_map == null) return [];
    final result = <MapEntry<CraftPdfName, CraftPdfObject>>[];
    for (final entry in _map!.entries) {
      var value = entry.value;
      if (value.objectKind() == PdfObjectType.indirectReference) {
        value = await (value as CraftPdfIndirectReference).targetObject(true) ??
            value;
      }
      result.add(MapEntry(entry.key, value));
    }
    return result;
  }

  /// Creates a clone excluding specified keys.
  CraftPdfDictionary cloneExcluding(List<CraftPdfName> excludeKeys) {
    final cloned = CraftPdfDictionary();
    if (_map != null) {
      for (final entry in _map!.entries) {
        if (!excludeKeys.contains(entry.key)) {
          cloned.put(entry.key, entry.value.clone());
        }
      }
    }
    return cloned;
  }

  /// Merges fields from another dictionary that don't exist in this one.
  Future<void> mergeDifferent(CraftPdfDictionary other) async {
    for (final key in other.keySet()) {
      if (!containsKey(key)) {
        final val = await other.get(key);
        if (val != null) {
          put(key, val);
        }
      }
    }
  }

  /// Releases the content.
  void releaseContent() {
    _map = null;
  }

  @override
  String toString() {
    if (hasBeenWritten()) {
      return indirectReference?.toString() ?? '<<>>';
    }
    final buffer = StringBuffer('<<');
    if (_map != null) {
      for (final entry in _map!.entries) {
        buffer.write(entry.key.toString());
        buffer.write(' ');
        final ref = entry.value.indirectHandle();
        buffer.write(ref?.toString() ?? entry.value.toString());
        buffer.write(' ');
      }
    }
    buffer.write('>>');
    return buffer.toString();
  }
}
