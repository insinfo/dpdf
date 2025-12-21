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
  PdfObject? get(PdfName key, [bool asDirect = true]) {
    if (_map == null) return null;
    if (!asDirect) {
      return _map![key];
    }
    final obj = _map![key];
    if (obj != null && obj.getObjectType() == PdfObjectType.indirectReference) {
      final resolved = (obj as PdfIndirectReference).getRefersTo(true);
      // Return resolved object if available, otherwise the reference itself
      return resolved ?? obj;
    }
    return obj;
  }

  /// Operator to get value by key.
  PdfObject? operator [](PdfName key) => get(key);

  /// Operator to set value by key.
  void operator []=(PdfName key, PdfObject value) => put(key, value);

  /// Returns the value as a PdfArray.
  PdfArray? getAsArray(PdfName key) {
    final direct = get(key, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.array) {
      return direct as PdfArray;
    }
    return null;
  }

  /// Returns the value as a PdfDictionary.
  PdfDictionary? getAsDictionary(PdfName key) {
    final direct = get(key, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.dictionary) {
      return direct as PdfDictionary;
    }
    return null;
  }

  /// Returns the value as a PdfNumber.
  PdfNumber? getAsNumber(PdfName key) {
    final direct = get(key, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.number) {
      return direct as PdfNumber;
    }
    return null;
  }

  /// Returns the value as a PdfName.
  PdfName? getAsName(PdfName key) {
    final direct = get(key, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.name) {
      return direct as PdfName;
    }
    return null;
  }

  /// Returns the value as a PdfString.
  PdfString? getAsString(PdfName key) {
    final direct = get(key, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.string) {
      return direct as PdfString;
    }
    return null;
  }

  /// Returns the value as a PdfBoolean.
  PdfBoolean? getAsBoolean(PdfName key) {
    final direct = get(key, true);
    if (direct != null && direct.getObjectType() == PdfObjectType.boolean) {
      return direct as PdfBoolean;
    }
    return null;
  }

  /// Returns the value as a double.
  double? getAsFloat(PdfName key) {
    final number = getAsNumber(key);
    return number?.doubleValue();
  }

  /// Returns the value as an int.
  int? getAsInt(PdfName key) {
    final number = getAsNumber(key);
    return number?.intValue();
  }

  /// Returns the value as a bool.
  bool? getAsBool(PdfName key) {
    final b = getAsBoolean(key);
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
  Iterable<PdfObject> values([bool asDirects = true]) {
    if (_map == null) return [];
    if (!asDirects) {
      return _map!.values;
    }
    return _map!.values.map((obj) {
      if (obj.getObjectType() == PdfObjectType.indirectReference) {
        return (obj as PdfIndirectReference).getRefersTo(true) ?? obj;
      }
      return obj;
    });
  }

  /// Returns all entries.
  Iterable<MapEntry<PdfName, PdfObject>> entrySet() {
    if (_map == null) return [];
    return _map!.entries.map((entry) {
      var value = entry.value;
      if (value.getObjectType() == PdfObjectType.indirectReference) {
        value = (value as PdfIndirectReference).getRefersTo(true) ?? value;
      }
      return MapEntry(entry.key, value);
    });
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
  void mergeDifferent(PdfDictionary other) {
    for (final key in other.keySet()) {
      if (!containsKey(key)) {
        put(key, other.get(key)!);
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
