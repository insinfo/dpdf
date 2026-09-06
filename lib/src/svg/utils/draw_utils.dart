import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/kernel/geom/affine_transform.dart';
import 'package:dpdf/src/io/source/byte_utils.dart';

/// Small utility class that contains methods for drawing shapes.
class DrawUtils {
  DrawUtils._();

  /// Draw an arc on the passed canvas, enclosed by the rectangle for which two opposite corners are specified.
  static void arc(double x1, double y1, double x2, double y2, double startAng,
      double extent, PdfCanvas cv,
      [AffineTransform? transform]) {
    cv.arc(x1, y1, x2, y2, startAng, extent, transform);
  }

  /// Perform stroke or fill operation for closed figure (e.g. Ellipse, Polygon, Circle).
  static void doStrokeOrFillForClosedFigure(
      String? fillRuleRawValue, PdfCanvas currentCanvas, bool doStroke) {
    if (ByteUtils.equalsIgnoreCase(
        SvgValues.FILL_RULE_EVEN_ODD, fillRuleRawValue)) {
      if (doStroke) {
        currentCanvas.closePathEoFillStroke();
      } else {
        currentCanvas.eoFill();
      }
    } else {
      if (doStroke) {
        currentCanvas.closePathFillStroke();
      } else {
        currentCanvas.fill();
      }
    }
  }
}
