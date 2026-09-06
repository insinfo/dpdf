import 'package:dpdf/src/kernel/geom/point.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';

/// A rectangle adapted for working with text elements.
class TextRectangle extends Rectangle {
  /// The y coordinate of the line on which the text is located.
  double textBaseLineYCoordinate;

  /// Create new instance of text rectangle.
  TextRectangle(double x, double y, double width, double height,
      this.textBaseLineYCoordinate)
      : super(x, y, width, height);

  /// Return the far right point of the rectangle with y on the baseline.
  Point getTextBaseLineRightPoint() {
    return Point(getRight(), textBaseLineYCoordinate);
  }
}
