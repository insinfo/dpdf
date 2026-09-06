import 'i_simple_list.dart';

/// A list which allows null elements without allocating memory for them.
///
/// In the rest of cases it behaves like a usual List and should have
/// the same complexity (because keys are unique integers, so collisions
/// are impossible).
class NullUnlimitedList<T> implements ISimpleList<T> {
  final Map<int, T> _map = {};
  int _size = 0;

  /// Creates a new instance of NullUnlimitedList.
  NullUnlimitedList();

  @override
  void add(T element) {
    // ignore: unnecessary_null_comparison
    if (element == null) {
      _size++;
    } else {
      int position = _size++;
      _map[position] = element;
    }
  }

  /// Adds an element at the specified index.
  /// In worst scenario O(n^2) but mostly impossible because keys shouldn't have
  /// collisions at all (they are integers). So in average should be O(n).
  @override
  void addAt(int index, T element) {
    if (index < 0 || index > _size) {
      return;
    }
    _size++;
    // Shifts the element currently at that position (if any) and any
    // subsequent elements to the right (adds one to their indices).
    T? previous = _map[index];
    for (int i = index + 1; i < _size; i++) {
      T? currentToAdd = previous;
      previous = _map[i];
      set(i, currentToAdd as T);
    }
    set(index, element);
  }

  /// Average O(1), worst O(n) (mostly impossible when keys are integers)
  @override
  T? get(int index) {
    return _map[index];
  }

  /// Average O(1), worst O(n) (mostly impossible when keys are integers)
  @override
  T? set(int index, T element) {
    // ignore: unnecessary_null_comparison
    if (element == null) {
      _map.remove(index);
    } else {
      _map[index] = element;
    }
    return element;
  }

  @override
  int indexOf(Object? element) {
    if (element == null) {
      for (int i = 0; i < _size; i++) {
        if (!_map.containsKey(i)) {
          return i;
        }
      }
      return -1;
    }
    for (final entry in _map.entries) {
      if (element == entry.value) {
        return entry.key;
      }
    }
    return -1;
  }

  /// In worst scenario O(n^2) but mostly impossible because keys shouldn't have
  /// collisions at all (they are integers). So in average should be O(n).
  @override
  void removeAt(int index) {
    if (index < 0 || index >= _size) {
      return;
    }
    _map.remove(index);
    // Shifts any subsequent elements to the left (subtracts one from their indices).
    T? previous = _map[_size - 1];
    int offset = 2;
    for (int i = _size - offset; i >= index; i--) {
      T? current = previous;
      previous = _map[i];
      set(i, current as T);
    }
    _map.remove(--_size);
  }

  @override
  int size() => _size;

  @override
  bool isEmpty() => _size == 0;
}
