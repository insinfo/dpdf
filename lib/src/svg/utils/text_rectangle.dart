import 'package:dpdf/src/kernel/geom/point.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';

/// A rectangle adapted for working with text elements.
class TextRectangle extends Rectangle {
  /// Vertical position of the text baseline.
  double textBaseLineYCoordinate;

  /// Create new instance of text rectangle.
  TextRectangle(super.x, super.y, super.width, super.height,
      this.textBaseLineYCoordinate);

  /// Returns the rightmost point on the text baseline.
  Point getTextBaseLineRightPoint() {
    return Point(getRight(), textBaseLineYCoordinate);
  }
}
