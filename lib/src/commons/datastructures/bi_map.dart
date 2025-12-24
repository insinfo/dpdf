/// A simple bi-directional map.
///
/// Allows lookup by both key and value in O(1) time.
class BiMap<K, V> {
  final Map<K, V> _map = {};
  final Map<V, K> _inverseMap = {};

  /// Creates a new BiMap instance.
  BiMap();

  /// Puts the entry into the map.
  ///
  /// If the key already exists, the value will be overwritten.
  /// If the value already exists, the key will be overwritten.
  /// If both key and value already exist, the entry will be overwritten.
  /// If neither key nor value already exist, the entry will be added.
  void put(K k, V v) {
    // Remove old mappings if they exist
    if (_map.containsKey(k)) {
      _inverseMap.remove(_map[k]);
    }
    if (_inverseMap.containsKey(v)) {
      _map.remove(_inverseMap[v]);
    }
    _map[k] = v;
    _inverseMap[v] = k;
  }

  /// Gets the value by key.
  V? getByKey(K key) => _map[key];

  /// Gets the key by value.
  K? getByValue(V value) => _inverseMap[value];

  /// Removes the entry by key.
  void removeByKey(K k) {
    final v = _map.remove(k);
    if (v != null) {
      _inverseMap.remove(v);
    }
  }

  /// Removes the entry by value.
  void removeByValue(V v) {
    final k = _inverseMap.remove(v);
    if (k != null) {
      _map.remove(k);
    }
  }

  /// Gets the size of the map.
  int size() => _map.length;

  /// Removes all entries from the map.
  void clear() {
    _map.clear();
    _inverseMap.clear();
  }

  /// Checks if the map is empty.
  bool isEmpty() => _map.isEmpty;

  /// Checks if the map contains the key.
  bool containsKey(K k) => _map.containsKey(k);

  /// Checks if the map contains the value.
  bool containsValue(V v) => _inverseMap.containsKey(v);

  /// Returns all keys.
  Iterable<K> get keys => _map.keys;

  /// Returns all values.
  Iterable<V> get values => _map.values;
}
