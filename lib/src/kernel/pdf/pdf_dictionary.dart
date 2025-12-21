import 'pdf_object.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_string.dart';
import 'pdf_boolean.dart';
import 'pdf_array.dart' show PdfArray;

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
  int getObjectType() => PdfObjectType.dictionary;

  @override
  PdfObject clone() {
    final cloned = PdfDictionary();
    if (_map != null) {
      for (final entry in _map!.entries) {
        cloned.put(entry.key, entry.value.clone());
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

  /// Returns true if this PdfDictionary contains the specified key.
  bool containsKey(PdfName key) => _map?.containsKey(key) ?? false;

  /// Returns true if this PdfDictionary contains the specified value.
  bool containsValue(PdfObject value) => _map?.containsValue(value) ?? false;

  /// Returns the value associated with this key.
  ///
  /// If [asDirect] is true and the value is an indirect reference,
  /// attempts to resolve it. If the reference cannot be resolved,
  /// returns the reference itself.
  Future<PdfObject?> get(PdfName key, [bool asDirect = true]) async {
    if (_map == null) return null;
    final obj = _map![key];
    if (asDirect &&
        obj != null &&
        obj.getObjectType() == PdfObjectType.indirectReference) {
      final resolved = await (obj as PdfIndirectReference).getRefersTo(true);
      // Return resolved object if available, otherwise the reference itself
      return resolved ?? obj;
    }
    return obj;
  }

  /// Returns the value as a PdfArray.
  Future<PdfArray?> getAsArray(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.array) {
      return direct as PdfArray;
    }
    return null;
  }

  /// Returns the value as a PdfDictionary.
  Future<PdfDictionary?> getAsDictionary(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.dictionary) {
      return direct as PdfDictionary;
    }
    return null;
  }

  /// Returns the value as a PdfNumber.
  Future<PdfNumber?> getAsNumber(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.number) {
      return direct as PdfNumber;
    }
    return null;
  }

  /// Returns the value as a PdfName.
  Future<PdfName?> getAsName(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.name) {
      return direct as PdfName;
    }
    return null;
  }

  /// Returns the value as a PdfString.
  Future<PdfString?> getAsString(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.string) {
      return direct as PdfString;
    }
    return null;
  }

  /// Returns the value as a PdfBoolean.
  Future<PdfBoolean?> getAsBoolean(PdfName key) async {
    final direct = await get(key, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.boolean) {
      return direct as PdfBoolean;
    }
    return null;
  }

  /// Returns the value as a double.
  Future<double?> getAsFloat(PdfName key) async {
    final number = await getAsNumber(key);
    return number?.doubleValue();
  }

  /// Returns the value as an int.
  Future<int?> getAsInt(PdfName key) async {
    final number = await getAsNumber(key);
    return number?.intValue();
  }

  /// Returns the value as a bool.
  Future<bool?> getAsBool(PdfName key) async {
    final b = await getAsBoolean(key);
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
      if (obj.getObjectType() == PdfObjectType.indirectReference) {
        result
            .add(await (obj as PdfIndirectReference).getRefersTo(true) ?? obj);
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
      if (value.getObjectType() == PdfObjectType.indirectReference) {
        value =
            await (value as PdfIndirectReference).getRefersTo(true) ?? value;
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
    if (isFlushed()) {
      return indirectReference?.toString() ?? '<<>>';
    }
    final buffer = StringBuffer('<<');
    if (_map != null) {
      for (final entry in _map!.entries) {
        buffer.write(entry.key.toString());
        buffer.write(' ');
        final ref = entry.value.getIndirectReference();
        buffer.write(ref?.toString() ?? entry.value.toString());
        buffer.write(' ');
      }
    }
    buffer.write('>>');
    return buffer.toString();
  }
}
