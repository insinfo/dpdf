import 'pdf_object.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_string.dart';
import 'pdf_boolean.dart';
import 'pdf_array.dart' show PdfArray;
import 'pdf_stream.dart';

/// A representation of a Dictionary as described by the PDF Specification.
///
/// A Dictionary is a mapping between keys and values. Keys are [PdfName]s
/// and the values are [PdfObject]s. Each key can only be associated with
/// one value.
class PdfDictionary extends PdfObject {
  /// The internal map.
  Map<PdfName, PdfObject>? _map;

  /// Gets the internal map.
  Map<PdfName, PdfObject>? getMap() => _map;

  /// Creates a new PdfDictionary instance.
  PdfDictionary() {
    _map = <PdfName, PdfObject>{};
  }

  /// Creates a new PdfDictionary from a map.
  PdfDictionary.fromMap(Map<PdfName, PdfObject> map) {
    _map = Map<PdfName, PdfObject>.from(map);
  }

  /// Creates a new PdfDictionary from entries.
  PdfDictionary.fromEntries(Iterable<MapEntry<PdfName, PdfObject>> entries) {
    _map = Map<PdfName, PdfObject>.fromEntries(entries);
  }

  /// Creates a new PdfDictionary from another PdfDictionary.
  PdfDictionary.fromDictionary(PdfDictionary dictionary) {
    _map = Map<PdfName, PdfObject>.from(dictionary._map ?? {});
  }

  @override
  int objectKind() => PdfObjectType.dictionary;

  @override
  PdfObject clone() {
    final cloned = PdfDictionary();
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
  PdfObject newInstance() {
    return PdfDictionary();
  }

  /// Returns the number of key-value pairs.
  int size() => _map?.length ?? 0;

  /// Returns true if there are no key-value pairs.
  bool isEmpty() => _map?.isEmpty ?? true;

  /// Tests membership of a dictionary key.
  bool containsKey(PdfName key) => _map?.containsKey(key) ?? false;

  /// Tests membership of a dictionary value.
  bool containsValue(PdfObject value) => _map?.containsValue(value) ?? false;

  /// Returns the value associated with this key.
  ///
  /// If [asDirect] is true and the value is an indirect reference,
  /// attempts to resolve it. If the reference cannot be resolved,
  /// returns the reference itself. By default the raw object (including
  /// indirect references) is returned to allow callers to decide when
  /// dereferencing is appropriate.
  Future<PdfObject?> get(PdfName key, [bool asDirect = false]) async {
    if (_map == null) return null;
    final obj = _map![key];
    if (asDirect &&
        obj != null &&
        obj.objectKind() == PdfObjectType.indirectReference) {
      final resolved = await (obj as PdfIndirectReference).targetObject(true);
      // Return resolved object if available, otherwise the reference itself
      return resolved ?? obj;
    }
    return obj;
  }

  /// Returns the value as a PdfArray.
  Future<PdfArray?> arrayEntry(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.array) {
      return direct as PdfArray;
    }
    return null;
  }

  /// Returns the value as a PdfDictionary.
  Future<PdfDictionary?> dictionaryEntry(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.dictionary) {
      return direct as PdfDictionary;
    }
    return null;
  }

  /// Returns the value as a PdfStream.
  Future<PdfStream?> streamEntry(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.stream) {
      return direct as PdfStream;
    }
    return null;
  }

  /// Returns the value as a PdfNumber.
  Future<PdfNumber?> numberEntry(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.number) {
      return direct as PdfNumber;
    }
    return null;
  }

  /// Returns the value as a PdfNumber synchronously (does not resolve indirect references).
  PdfNumber? getNumberSync(PdfName key) {
    final obj = _map?[key];
    if (obj != null && obj.objectKind() == PdfObjectType.number) {
      return obj as PdfNumber;
    }
    return null;
  }

  /// Returns the value as a PdfBoolean synchronously (does not resolve indirect references).
  PdfBoolean? getBooleanSync(PdfName key) {
    final obj = _map?[key];
    if (obj != null && obj.objectKind() == PdfObjectType.boolean) {
      return obj as PdfBoolean;
    }
    return null;
  }

  /// Returns the value as a PdfName.
  Future<PdfName?> nameEntry(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.name) {
      return direct as PdfName;
    }
    return null;
  }

  /// Returns the value as a PdfString.
  Future<PdfString?> stringEntry(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.string) {
      return direct as PdfString;
    }
    return null;
  }

  /// Returns the value as a PdfBoolean.
  Future<PdfBoolean?> booleanEntry(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.objectKind() == PdfObjectType.boolean) {
      return direct as PdfBoolean;
    }
    return null;
  }

  /// Returns the value as a double.
  Future<double?> decimalEntry(PdfName key) async {
    final number = await numberEntry(key);
    return number?.doubleValue();
  }

  /// Returns the value as an int.
  Future<int?> integerEntry(PdfName key) async {
    final number = await numberEntry(key);
    return number?.intValue();
  }

  /// Returns the value as a bool.
  Future<bool?> flagEntry(PdfName key) async {
    final b = await booleanEntry(key);
    return b?.getValue();
  }

  /// Inserts the value with the specified key.
  PdfObject? put(PdfName key, PdfObject value) {
    if (_map == null) return null;
    final old = _map![key];
    _map![key] = value;
    return old;
  }

  /// Removes the specified key.
  PdfObject? remove(PdfName key) {
    return _map?.remove(key);
  }

  /// Inserts all key-value pairs from another dictionary.
  void putAll(PdfDictionary d) {
    if (d._map != null) {
      _map?.addAll(d._map!);
    }
  }

  /// Removes all key-value pairs.
  void clear() {
    _map?.clear();
  }

  /// Returns all the keys as a Set.
  Set<PdfName> keySet() {
    return _map?.keys.toSet() ?? <PdfName>{};
  }

  /// Returns all the values.
  Future<Iterable<PdfObject>> values([bool asDirects = true]) async {
    if (_map == null) return [];
    if (!asDirects) {
      return _map!.values;
    }
    final result = <PdfObject>[];
    for (final obj in _map!.values) {
      if (obj.objectKind() == PdfObjectType.indirectReference) {
        result
            .add(await (obj as PdfIndirectReference).targetObject(true) ?? obj);
      } else {
        result.add(obj);
      }
    }
    return result;
  }

  /// Returns all entries.
  Future<Iterable<MapEntry<PdfName, PdfObject>>> entrySet() async {
    if (_map == null) return [];
    final result = <MapEntry<PdfName, PdfObject>>[];
    for (final entry in _map!.entries) {
      var value = entry.value;
      if (value.objectKind() == PdfObjectType.indirectReference) {
        value =
            await (value as PdfIndirectReference).targetObject(true) ?? value;
      }
      result.add(MapEntry(entry.key, value));
    }
    return result;
  }

  /// Creates a clone excluding specified keys.
  PdfDictionary cloneExcluding(List<PdfName> excludeKeys) {
    final cloned = PdfDictionary();
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
  Future<void> mergeDifferent(PdfDictionary other) async {
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
