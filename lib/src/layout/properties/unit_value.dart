class CraftUnitValue {
  static const int POINT = 1;
  static const int PERCENT = 2;

  int unitType;
  double value;

  CraftUnitValue(this.unitType, this.value);

  static CraftUnitValue createPointValue(double value) {
    return CraftUnitValue(POINT, value);
  }

  static CraftUnitValue createPercentValue(double value) {
    return CraftUnitValue(PERCENT, value);
  }

  bool isPointValue() {
    return unitType == POINT;
  }

  bool isPercentValue() {
    return unitType == PERCENT;
  }

  double getValue() {
    return value;
  }

  int getUnitType() {
    return unitType;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CraftUnitValue &&
        other.unitType == unitType &&
        (other.value - value).abs() < 0.0001; // basic float comparison
  }

  @override
  int get hashCode => unitType.hashCode ^ value.hashCode;

  @override
  String toString() {
    return 'UnitValue{unitType: $unitType, value: $value}';
  }
}
