import 'dart:math';

import 'package:dpdf/src/layout/minmaxwidth/min_max_width_utils.dart';

class MinMaxWidth {
  double childrenMinWidth;
  double childrenMaxWidth;
  double additionalWidth;

  MinMaxWidth([double additionalWidth = 0.0])
      : this.full(0.0, 0.0, additionalWidth);

  MinMaxWidth.full(
      this.childrenMinWidth, this.childrenMaxWidth, this.additionalWidth);

  double getChildrenMinWidth() {
    return childrenMinWidth;
  }

  void setChildrenMinWidth(double childrenMinWidth) {
    this.childrenMinWidth = childrenMinWidth;
  }

  double getChildrenMaxWidth() {
    return childrenMaxWidth;
  }

  void setChildrenMaxWidth(double childrenMaxWidth) {
    this.childrenMaxWidth = childrenMaxWidth;
  }

  double getAdditionalWidth() {
    return additionalWidth;
  }

  void setAdditionalWidth(double additionalWidth) {
    this.additionalWidth = additionalWidth;
  }

  double getMaxWidth() {
    return min(
        childrenMaxWidth + additionalWidth, MinMaxWidthUtils.getInfWidth());
  }

  double getMinWidth() {
    return min(childrenMinWidth + additionalWidth, getMaxWidth());
  }

  @override
  String toString() {
    return "min=${childrenMinWidth + additionalWidth}, max=${childrenMaxWidth + additionalWidth}";
  }
}
