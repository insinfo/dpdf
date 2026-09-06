import 'dart:math';
import 'dart:typed_data';

/// Bezier utility class.
class Bezier {
  Bezier._();

  /// Calculates the Bezier curve points for an arc.
  static List<Float64List> bezierArc(double x1, double y1, double x2, double y2,
      double startAng, double extent) {
    double tmp;
    if (x1 > x2) {
      tmp = x1;
      x1 = x2;
      x2 = tmp;
    }
    if (y2 > y1) {
      tmp = y1;
      y1 = y2;
      y2 = tmp;
    }
    double fragAngle;
    int nFrag;
    if (extent.abs() <= 90.0) {
      fragAngle = extent;
      nFrag = 1;
    } else {
      nFrag = (extent.abs() / 90.0).ceil();
      fragAngle = extent / nFrag;
    }

    double xCen = (x1 + x2) / 2.0;
    double yCen = (y1 + y2) / 2.0;
    double rx = (x2 - x1) / 2.0;
    double ry = (y2 - y1) / 2.0;
    double halfAng = (fragAngle * pi / 360.0);
    double kappa = (4.0 / 3.0 * (1.0 - cos(halfAng)) / sin(halfAng)).abs();
    List<Float64List> pointList = [];

    for (int iter = 0; iter < nFrag; ++iter) {
      double theta0 = ((startAng + iter * fragAngle) * pi / 180.0);
      double theta1 = ((startAng + (iter + 1) * fragAngle) * pi / 180.0);
      double cos0 = cos(theta0);
      double cos1 = cos(theta1);
      double sin0 = sin(theta0);
      double sin1 = sin(theta1);

      if (fragAngle > 0.0) {
        pointList.add(Float64List.fromList([
          xCen + rx * cos0,
          yCen - ry * sin0,
          xCen + rx * (cos0 - kappa * sin0),
          yCen - ry * (sin0 + kappa * cos0),
          xCen + rx * (cos1 + kappa * sin1),
          yCen - ry * (sin1 - kappa * cos1),
          xCen + rx * cos1,
          yCen - ry * sin1
        ]));
      } else {
        pointList.add(Float64List.fromList([
          xCen + rx * cos0,
          yCen - ry * sin0,
          xCen + rx * (cos0 + kappa * sin0),
          yCen - ry * (sin0 - kappa * cos0),
          xCen + rx * (cos1 - kappa * sin1),
          yCen - ry * (sin1 + kappa * cos1),
          xCen + rx * cos1,
          yCen - ry * sin1
        ]));
      }
    }
    return pointList;
  }
}
