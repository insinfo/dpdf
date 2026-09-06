/// Simple tuple container that holds two elements.
class Tuple2<T1, T2> {
  final T1 first;
  final T2 second;

  /// Creates a new instance of Tuple2 with given elements.
  const Tuple2(this.first, this.second);

  /// Get the first element.
  T1 getFirst() => first;

  /// Get the second element.
  T2 getSecond() => second;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Tuple2<T1, T2>) return false;
    return first == other.first && second == other.second;
  }

  @override
  int get hashCode => Object.hash(first, second);

  @override
  String toString() => 'Tuple2{first=$first, second=$second}';
}

/// Simple tuple container that holds three elements.
class Tuple3<T1, T2, T3> {
  final T1 first;
  final T2 second;
  final T3 third;

  /// Creates a new instance of Tuple3 with given elements.
  const Tuple3(this.first, this.second, this.third);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Tuple3<T1, T2, T3>) return false;
    return first == other.first &&
        second == other.second &&
        third == other.third;
  }

  @override
  int get hashCode => Object.hash(first, second, third);

  @override
  String toString() => 'Tuple3{first=$first, second=$second, third=$third}';
}
