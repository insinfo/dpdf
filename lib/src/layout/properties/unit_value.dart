class UnitValue {
  static const int POINT = 1;
  static const int PERCENT = 2;

  int unitType;
  double value;

  UnitValue(this.unitType, this.value);

  static UnitValue createPointValue(double value) {
    return UnitValue(POINT, value);
  }

  static UnitValue createPercentValue(double value) {
    return UnitValue(PERCENT, value);
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
}
