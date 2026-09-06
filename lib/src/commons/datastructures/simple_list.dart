/// Indexed storage with insertion, replacement and removal operations.
abstract interface class SimpleList<T> {
  /// Adds an element to the end of the list.
  void add(T element);

  /// Adds an element to the list at the specified index.
  void addAt(int index, T element);

  /// Returns the element at the specified index.
  T? get(int index);

  /// Replaces the element at the specified index with the specified element.
  T? set(int index, T element);

  /// Returns the index of the first occurrence of the specified element in the list,
  /// or -1 if the list does not contain the element.
  int indexOf(Object? element);

  /// Removes the element at the specified index.
  void removeAt(int index);

  /// Returns the number of elements in the list.
  int size();

  /// Returns true if the list contains no elements, false otherwise.
  bool isEmpty();
}
