/// Integer lookup backed by the Dart SDK map implementation.
/// Missing entries read as zero; key iteration follows insertion order.
class CraftIntHashtable {
  final Map<int, int> _values = {};

  CraftIntHashtable();
  CraftIntHashtable.withInitialCapacity(int initialCapacity)
      : this.withCapacity(initialCapacity, 0.75);
  CraftIntHashtable.withCapacity(int initialCapacity, double loadFactor) {
    if (initialCapacity < 0) {
      throw ArgumentError.value(
          initialCapacity, 'initialCapacity', 'Must be nonnegative');
    }
    if (!loadFactor.isFinite || loadFactor <= 0) {
      throw ArgumentError.value(
          loadFactor, 'loadFactor', 'Must be finite and positive');
    }
  }

  int size() => _values.length;
  bool isEmpty() => _values.isEmpty;
  bool contains(int value) => _values.containsValue(value);
  bool containsValue(int value) => _values.containsValue(value);
  bool containsKey(int key) => _values.containsKey(key);
  int get(int key) => _values[key] ?? 0;
  int put(int key, int value) {
    final previous = get(key);
    _values[key] = value;
    return previous;
  }

  int remove(int key) => _values.remove(key) ?? 0;
  void clear() => _values.clear();
  List<int> getKeys() => _values.keys.toList();
  List<int> toOrderedKeys() => getKeys()..sort();
  int getOneKey() => _values.isEmpty ? 0 : _values.keys.first;
  CraftIntHashtable clone() => CraftIntHashtable().._values.addAll(_values);
  int operator [](int key) => get(key);
  void operator []=(int key, int value) {
    _values[key] = value;
  }
}
