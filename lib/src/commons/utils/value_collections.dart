/// Value comparisons used by PDF objects, without a collection package.
abstract final class ValueCollections {
  static bool listsEqual(List<Object?>? left, List<Object?>? right) {
    if (identical(left, right)) return true;
    if (left == null || right == null || left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static int listHash(List<Object?>? values) =>
      values == null ? 0 : Object.hashAll(values);

  static bool mapsEqual(
      Map<Object?, Object?> left, Map<Object?, Object?> right) {
    if (left.length != right.length) return false;
    return left.entries.every((entry) =>
        right.containsKey(entry.key) && right[entry.key] == entry.value);
  }

  static int mapHash(Map<Object?, Object?> values) => Object.hashAllUnordered(
      values.entries.map((entry) => Object.hash(entry.key, entry.value)));

  static bool setsEqual(Set<Object?> left, Set<Object?> right) =>
      left.length == right.length && left.every(right.contains);

  static int setHash(Set<Object?> values) => Object.hashAllUnordered(values);
}
