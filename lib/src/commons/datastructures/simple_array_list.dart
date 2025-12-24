import 'i_simple_list.dart';

/// Portable implementation of ArrayList.
class SimpleArrayList<T> implements ISimpleList<T> {
  final List<T> _list;

  /// Creates a new instance of SimpleArrayList.
  SimpleArrayList() : _list = [];

  /// Creates a new instance of SimpleArrayList with the specified initial capacity.
  SimpleArrayList.withCapacity(int initialCapacity)
      : _list = List<T>.empty(growable: true);

  @override
  void add(T element) {
    _list.add(element);
  }

  @override
  void addAt(int index, T element) {
    _list.insert(index, element);
  }

  @override
  T? get(int index) {
    if (index < 0 || index >= _list.length) return null;
    return _list[index];
  }

  @override
  T? set(int index, T element) {
    if (index < 0 || index >= _list.length) return null;
    T value = _list[index];
    _list[index] = element;
    return value;
  }

  @override
  int indexOf(Object? element) {
    return _list.indexOf(element as T);
  }

  @override
  void removeAt(int index) {
    if (index >= 0 && index < _list.length) {
      _list.removeAt(index);
    }
  }

  @override
  int size() => _list.length;

  @override
  bool isEmpty() => _list.isEmpty;

  /// Returns the underlying list.
  List<T> toList() => List.from(_list);
}
