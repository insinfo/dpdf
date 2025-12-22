import '../pdf/pdf_array.dart';
import '../pdf/pdf_number.dart';

/// Class that represent rectangle object.
class Rectangle {
  static const double EPS = 1e-4;

  double x;
  double y;
  double width;
  double height;

  /// Creates new instance.
  Rectangle(this.x, this.y, this.width, this.height);

  /// Creates new instance of rectangle with (0, 0) as the lower left point.
  Rectangle.withSize(double width, double height) : this(0, 0, width, height);

  /// Creates the copy of given [Rectangle]
  Rectangle.fromRectangle(Rectangle rect)
      : this(rect.x, rect.y, rect.width, rect.height);

  /// Gets the X coordinate of lower left point.
  double getX() => x;

  /// Sets the X coordinate of lower left point.
  void setX(double x) => this.x = x;

  /// Gets the Y coordinate of lower left point.
  double getY() => y;

  /// Sets the Y coordinate of lower left point.
  void setY(double y) => this.y = y;

  /// Gets the width of rectangle.
  double getWidth() => width;

  /// Sets the width of rectangle.
  void setWidth(double width) => this.width = width;

  /// Gets the height of rectangle.
  double getHeight() => height;

  /// Sets the height of rectangle.
  void setHeight(double height) => this.height = height;

  /// Gets the X coordinate of the left edge of the rectangle.
  double getLeft() => x;

  /// Gets the X coordinate of the right edge of the rectangle.
  double getRight() => x + width;

  /// Gets the Y coordinate of the upper edge of the rectangle.
  double getTop() => y + height;

  /// Gets the Y coordinate of the lower edge of the rectangle.
  double getBottom() => y;

  /// Converts rectangle to a [PdfArray].
  PdfArray toPdfArray() {
    return PdfArray()
      ..add(PdfNumber(x))
      ..add(PdfNumber(y))
      ..add(PdfNumber(x + width))
      ..add(PdfNumber(y + height));
  }

  /// Creates a [Rectangle] from a [PdfArray].
  static Future<Rectangle?> fromPdfArray(PdfArray? array) async {
    if (array == null || array.size() < 4) {
      return null;
    }
    final llx = (await array.getAsNumber(0))?.doubleValue() ?? 0.0;
    final lly = (await array.getAsNumber(1))?.doubleValue() ?? 0.0;
    final urx = (await array.getAsNumber(2))?.doubleValue() ?? 0.0;
    final ury = (await array.getAsNumber(3))?.doubleValue() ?? 0.0;
    return Rectangle(llx, lly, urx - llx, ury - lly);
  }

  @override
  String toString() {
    return 'Rectangle: ${width}x$height at ($x, $y)';
  }

  Rectangle clone() {
    return Rectangle(x, y, width, height);
  }

  bool equalsWithEpsilon(Rectangle other) {
    return (x - other.x).abs() < EPS &&
        (y - other.y).abs() < EPS &&
        (width - other.width).abs() < EPS &&
        (height - other.height).abs() < EPS;
  }

  void move(double dx, double dy) {
    x += dx;
    y += dy;
  }
}
