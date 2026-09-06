/// A hash map that uses primitive ints for the key rather than objects.
///
/// This is optimized for performance in cases where keys are integers.
class IntHashtable {
  int _count = 0;
  late List<_Entry?> _table;
  late int _threshold;
  final double _loadFactor;

  /// Constructs a new, empty hashtable with default capacity and load factor.
  IntHashtable() : this.withCapacity(150, 0.75);

  /// Constructs a new hashtable with the specified initial capacity.
  IntHashtable.withInitialCapacity(int initialCapacity)
      : this.withCapacity(initialCapacity, 0.75);

  /// Constructs a new hashtable with the specified initial capacity and load factor.
  IntHashtable.withCapacity(int initialCapacity, this._loadFactor) {
    if (initialCapacity < 0) {
      throw ArgumentError('Illegal Capacity: $initialCapacity');
    }
    if (_loadFactor <= 0) {
      throw ArgumentError('Illegal Load: $_loadFactor');
    }
    if (initialCapacity == 0) {
      initialCapacity = 1;
    }
    _table = List<_Entry?>.filled(initialCapacity, null);
    _threshold = (initialCapacity * _loadFactor).toInt();
  }

  /// Returns the number of keys in this hashtable.
  int size() => _count;

  /// Tests if this hashtable maps no keys to values.
  bool isEmpty() => _count == 0;

  /// Tests if some key maps into the specified value in this hashtable.
  bool contains(int value) {
    for (int i = _table.length - 1; i >= 0; i--) {
      for (_Entry? e = _table[i]; e != null; e = e.next) {
        if (e.value == value) return true;
      }
    }
    return false;
  }

  /// Returns true if this HashMap maps one or more keys to this value.
  bool containsValue(int value) => contains(value);

  /// Tests if the specified int is a key in this hashtable.
  bool containsKey(int key) {
    int index = (key & 0x7FFFFFFF) % _table.length;
    for (_Entry? e = _table[index]; e != null; e = e.next) {
      if (e.key == key) return true;
    }
    return false;
  }

  /// Returns the value to which the specified key is mapped.
  int get(int key) {
    int index = (key & 0x7FFFFFFF) % _table.length;
    for (_Entry? e = _table[index]; e != null; e = e.next) {
      if (e.key == key) return e.value;
    }
    return 0;
  }

  /// Increases the capacity and internally reorganizes this hashtable.
  void _rehash() {
    int oldCapacity = _table.length;
    List<_Entry?> oldMap = _table;
    int newCapacity = oldCapacity * 2 + 1;
    List<_Entry?> newMap = List<_Entry?>.filled(newCapacity, null);
    _threshold = (newCapacity * _loadFactor).toInt();
    _table = newMap;

    for (int i = oldCapacity - 1; i >= 0; i--) {
      for (_Entry? old = oldMap[i]; old != null;) {
        _Entry e = old;
        old = old.next;
        int index = (e.key & 0x7FFFFFFF) % newCapacity;
        e.next = newMap[index];
        newMap[index] = e;
      }
    }
  }

  /// Maps the specified key to the specified value in this hashtable.
  int put(int key, int value) {
    int index = (key & 0x7FFFFFFF) % _table.length;
    for (_Entry? e = _table[index]; e != null; e = e.next) {
      if (e.key == key) {
        int old = e.value;
        e.value = value;
        return old;
      }
    }
    if (_count >= _threshold) {
      _rehash();
      index = (key & 0x7FFFFFFF) % _table.length;
    }
    _Entry e = _Entry(key, value, _table[index]);
    _table[index] = e;
    _count++;
    return 0;
  }

  /// Removes the key (and its corresponding value) from this hashtable.
  int remove(int key) {
    int index = (key & 0x7FFFFFFF) % _table.length;
    _Entry? prev;
    for (_Entry? e = _table[index]; e != null; prev = e, e = e.next) {
      if (e.key == key) {
        if (prev != null) {
          prev.next = e.next;
        } else {
          _table[index] = e.next;
        }
        _count--;
        int oldValue = e.value;
        e.value = 0;
        return oldValue;
      }
    }
    return 0;
  }

  /// Clears this hashtable so that it contains no keys.
  void clear() {
    for (int i = _table.length - 1; i >= 0; i--) {
      _table[i] = null;
    }
    _count = 0;
  }

  /// Returns an array of ordered keys.
  List<int> toOrderedKeys() {
    List<int> res = getKeys();
    res.sort();
    return res;
  }

  /// Returns an array of all keys.
  List<int> getKeys() {
    List<int> res = [];
    for (int i = _table.length - 1; i >= 0; i--) {
      for (_Entry? e = _table[i]; e != null; e = e.next) {
        res.add(e.key);
      }
    }
    return res;
  }

  /// Returns one key from the hashtable.
  int getOneKey() {
    if (_count == 0) return 0;
    for (int i = _table.length - 1; i >= 0; i--) {
      if (_table[i] != null) return _table[i]!.key;
    }
    return 0;
  }

  /// Creates a clone of this hashtable.
  IntHashtable clone() {
    IntHashtable t = IntHashtable.withCapacity(_table.length, _loadFactor);
    t._table = List<_Entry?>.filled(_table.length, null);
    for (int i = _table.length - 1; i >= 0; i--) {
      t._table[i] = _table[i]?._clone();
    }
    t._count = _count;
    return t;
  }

  /// Operator access.
  int operator [](int key) => get(key);
  void operator []=(int key, int value) => put(key, value);
}

/// Entry class for IntHashtable.
class _Entry {
  int key;
  int value;
  _Entry? next;

  _Entry(this.key, this.value, this.next);

  int getKey() => key;
  int getValue() => value;

  _Entry _clone() {
    return _Entry(key, value, next?._clone());
  }

  @override
  String toString() => '$key=$value';
}
