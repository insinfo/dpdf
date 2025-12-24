import 'dart:collection';

/// Helper class for internal usage only, providing Java-like collection utilities.
/// TODO ? Be aware that its API and functionality may be changed in future.
class JavaCollectionsUtil {
  JavaCollectionsUtil._();

  /// Returns an empty unmodifiable list.
  static List<T> emptyList<T>() => const [];

  /// Returns an empty unmodifiable map.
  static Map<K, V> emptyMap<K, V>() => const {};

  /// Returns an empty unmodifiable set.
  static Set<T> emptySet<T>() => const {};

  /// Returns an empty iterator.
  static Iterator<T> emptyIterator<T>() => _EmptyIterator<T>();

  /// Returns an unmodifiable view of the specified list.
  static List<T> unmodifiableList<T>(List<T> list) {
    return UnmodifiableListView(list);
  }

  /// Returns an unmodifiable view of the specified map.
  static Map<K, V> unmodifiableMap<K, V>(Map<K, V> map) {
    return UnmodifiableMapView(map);
  }

  /// Returns an unmodifiable view of the specified set.
  static Set<T> unmodifiableSet<T>(Set<T> set) {
    return UnmodifiableSetView(set);
  }

  /// Returns a singleton set containing only the specified object.
  static Set<T> singleton<T>(T o) => {o};

  /// Returns a singleton list containing only the specified object.
  static List<T> singletonList<T>(T o) => [o];

  /// Returns a singleton map containing only the specified key-value pair.
  static Map<K, V> singletonMap<K, V>(K key, V value) => {key: value};

  /// Sorts the specified list according to the natural ordering of its elements.
  static void sort<T>(List<T> list, [Comparator<T>? comparator]) {
    if (comparator != null) {
      list.sort(comparator);
    } else {
      list.sort();
    }
  }

  /// Reverses the order of the elements in the specified list.
  static void reverse<T>(List<T> list) {
    final length = list.length;
    for (int i = 0; i < length ~/ 2; i++) {
      final temp = list[i];
      list[i] = list[length - 1 - i];
      list[length - 1 - i] = temp;
    }
  }

  /// Shuffles the list randomly.
  static void shuffle<T>(List<T> list) {
    list.shuffle();
  }

  /// Fills the list with the specified value.
  static void fill<T>(List<T> list, T value) {
    for (int i = 0; i < list.length; i++) {
      list[i] = value;
    }
  }

  /// Copies elements from src to dest.
  static void copy<T>(List<T> dest, List<T> src) {
    for (int i = 0; i < src.length && i < dest.length; i++) {
      dest[i] = src[i];
    }
  }

  /// Returns the minimum element of the given collection according to the natural ordering.
  static T min<T extends Comparable<T>>(Iterable<T> collection) {
    return collection.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
  }

  /// Returns the maximum element of the given collection according to the natural ordering.
  static T max<T extends Comparable<T>>(Iterable<T> collection) {
    return collection.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
  }

  /// Returns the frequency of the specified element in the collection.
  static int frequency<T>(Iterable<T> collection, T o) {
    int count = 0;
    for (final element in collection) {
      if (element == o) count++;
    }
    return count;
  }

  /// Replaces all occurrences of one element with another.
  static bool replaceAll<T>(List<T> list, T oldVal, T newVal) {
    bool replaced = false;
    for (int i = 0; i < list.length; i++) {
      if (list[i] == oldVal) {
        list[i] = newVal;
        replaced = true;
      }
    }
    return replaced;
  }

  /// Performs a binary search on a sorted list.
  static int binarySearch<T extends Comparable<T>>(List<T> list, T key) {
    int low = 0;
    int high = list.length - 1;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final cmp = list[mid].compareTo(key);

      if (cmp < 0) {
        low = mid + 1;
      } else if (cmp > 0) {
        high = mid - 1;
      } else {
        return mid;
      }
    }
    return -(low + 1);
  }
}

class _EmptyIterator<T> implements Iterator<T> {
  @override
  T get current => throw StateError('No element');

  @override
  bool moveNext() => false;
}

/// Unmodifiable set view.
class UnmodifiableSetView<T> extends SetBase<T> {
  final Set<T> _source;

  UnmodifiableSetView(this._source);

  @override
  bool add(T value) => throw UnsupportedError('Cannot add to unmodifiable set');

  @override
  bool contains(Object? element) => _source.contains(element);

  @override
  Iterator<T> get iterator => _source.iterator;

  @override
  int get length => _source.length;

  @override
  T? lookup(Object? element) {
    for (final e in _source) {
      if (e == element) return e;
    }
    return null;
  }

  @override
  bool remove(Object? value) =>
      throw UnsupportedError('Cannot remove from unmodifiable set');

  @override
  Set<T> toSet() => Set.of(_source);
}
