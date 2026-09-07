import 'dart:math' as math;

/// Class that represent point object with x and y coordinates.
class Point {
  double x;
  double y;

  /// Instantiates a new Point instance with 0 x and y.
  Point([this.x = 0, this.y = 0]);

  /// Instantiates a new Point instance based on other Point instance.
  Point.fromPoint(Point other) : this(other.getX(), other.getY());

  /// Gets x coordinate of the point.
  double getX() => x;

  /// Gets y coordinate of the point.
  double getY() => y;

  /// Gets location of point by creating a new copy.
  Point getLocation() => Point(x, y);

  /// Sets x and y double coordinates of the point.
  void setLocation(double x, double y) {
    this.x = x;
    this.y = y;
  }

  /// Moves the point by the specified offset.
  void move(double dx, double dy) {
    x += dx;
    y += dy;
  }

  /// The distance between this point and the second point which is defined by passed x and y coordinates.
  double distance(double px, double py) {
    return math.sqrt(_distanceSq(getX(), getY(), px, py));
  }

  /// The distance between this point and the second point.
  double distancePoint(Point p) {
    return distance(p.getX(), p.getY());
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is Point) {
      return x == other.x && y == other.y;
    }
    return false;
  }

  @override
  String toString() {
    return "Point: [x=$x,y=$y]";
  }

  @override
  int get hashCode => Object.hash(x, y);

  Point clone() => Point(x, y);

  static double _distanceSq(double x1, double y1, double x2, double y2) {
    x2 -= x1;
    y2 -= y1;
    return x2 * x2 + y2 * y2;
  }
}
