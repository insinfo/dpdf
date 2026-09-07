import 'package:dpdf/src/kernel/geom/point.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';

/// A rectangle adapted for working with text elements.
class CraftTextRectangle extends CraftRectangle {
  /// Vertical position of the text baseline.
  double textBaseLineYCoordinate;

  /// Create new instance of text rectangle.
  CraftTextRectangle(double x, double y, double width, double height,
      this.textBaseLineYCoordinate)
      : super(x, y, width, height);

  /// Returns the rightmost point on the text baseline.
  CraftPoint getTextBaseLineRightPoint() {
    return CraftPoint(getRight(), textBaseLineYCoordinate);
  }
}
