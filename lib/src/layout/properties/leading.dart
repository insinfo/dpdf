class Leading {
  static const int FIXED = 1;
  static const int MULTIPLIED = 2;

  final int type;
  final double value;

  Leading(this.type, this.value);

  int getType() => type;

  double getValue() => value;

  @override
  String toString() {
    return 'Leading{type: $type, value: $value}';
  }
}
