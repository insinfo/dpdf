import 'package:dpdf/src/kernel/geom/point.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';

/// A rectangle adapted for working with text elements.
class CraftTextRectangle extends CraftRectangle {
  /// Vertical position of the text baseline.
  double textBaseLineYCoordinate;

  /// Create new instance of text rectangle.
  CraftTextRectangle(super.x, super.y, super.width, super.height,
      this.textBaseLineYCoordinate);

  /// Returns the rightmost point on the text baseline.
  CraftPoint getTextBaseLineRightPoint() {
    return CraftPoint(getRight(), textBaseLineYCoordinate);
  }
}
