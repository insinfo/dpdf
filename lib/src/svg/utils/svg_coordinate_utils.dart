import 'dart:math' as math;
import 'package:pdfcraft/src/kernel/geom/rectangle.dart';
import 'package:pdfcraft/src/kernel/geom/vector.dart';
import 'package:pdfcraft/src/layout/properties/unit_value.dart';
import 'package:pdfcraft/src/styledxmlparser/css/util/css_dimension_parsing_utils.dart';
import 'package:pdfcraft/src/styledxmlparser/css/util/css_types_validation_utils.dart';
import 'package:pdfcraft/src/svg/exceptions/svg_exception_message_constant.dart';
import 'package:pdfcraft/src/svg/renderers/svg_draw_context.dart';
import 'package:pdfcraft/src/svg/svg_constants.dart';

class CraftSvgCoordinateUtils {
  CraftSvgCoordinateUtils._();

  static List<String> makeRelativeOperatorCoordinatesAbsolute(
      List<String> relativeCoordinates, List<double> currentCoordinates) {
    if (relativeCoordinates.length % currentCoordinates.length != 0) {
      throw ArgumentError(CraftSvgExceptionMessageConstant
          .COORDINATE_ARRAY_LENGTH_MUST_BY_DIVISIBLE_BY_CURRENT_COORDINATES_ARRAY_LENGTH);
    }
    List<String> absoluteOperators =
        List<String>.filled(relativeCoordinates.length, "");
    for (int i = 0; i < relativeCoordinates.length;) {
      for (int j = 0; j < currentCoordinates.length; j++, i++) {
        double relativeDouble = double.parse(relativeCoordinates[i]);
        relativeDouble += currentCoordinates[j];
        absoluteOperators[i] = relativeDouble.toString();
      }
    }
    return absoluteOperators;
  }

  static double calculateAngleBetweenTwoVectors(
      CraftVector vectorA, CraftVector vectorB) {
    return math
        .acos(vectorA.dot(vectorB) / (vectorA.length() * vectorB.length()));
  }

  static double getCoordinateForUserSpaceOnUse(String attributeValue,
      double defaultValue, double start, double length, double em, double rem) {
    double absoluteValue;
    CraftUnitValue? unitValue =
        CraftCssDimensionParsingUtils.parseLengthValueToPt(
            attributeValue, em, rem);
    if (unitValue == null) {
      absoluteValue = defaultValue;
    } else {
      if (unitValue.getUnitType() == CraftUnitValue.PERCENT) {
        absoluteValue = start + (length * unitValue.getValue() / 100);
      } else {
        absoluteValue = unitValue.getValue();
      }
    }
    return absoluteValue;
  }

  static double getCoordinateForObjectBoundingBox(
      String attributeValue, double defaultValue) {
    final normalized = attributeValue.trim();
    final accepted = <bool Function(String)>[
      CraftCssTypesValidationUtils.isPercentageValue,
      CraftCssTypesValidationUtils.isNumber,
      CraftCssTypesValidationUtils.isMetricValue,
      CraftCssTypesValidationUtils.isRelativeValue,
    ].any((validate) => validate(normalized));
    if (!accepted) return defaultValue;
    final numeric = RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?')
        .firstMatch(normalized);
    final amount = double.tryParse(numeric?.group(0) ?? '');
    return amount == null
        ? defaultValue
        : amount / (normalized.endsWith('%') ? 100 : 1);
  }

  static double calculateNormalizedDiagonalLength(CraftSvgDrawContext context) {
    CraftRectangle? viewPort = context.getCurrentViewPort();
    if (viewPort == null) return 0.0;
    double viewPortHeight = viewPort.getHeight();
    double viewPortWidth = viewPort.getWidth();
    return math.sqrt(
            viewPortHeight * viewPortHeight + viewPortWidth * viewPortWidth) /
        math.sqrt(2);
  }

  static CraftRectangle applyViewBox(CraftRectangle viewBox,
      CraftRectangle currentViewPort, String? align, String? meetOrSlice) {
    if (align == null ||
        (meetOrSlice != null &&
            meetOrSlice != SvgValues.MEET &&
            meetOrSlice != SvgValues.SLICE)) {
      return applyViewBox(
          viewBox, currentViewPort, SvgValues.XMID_YMID, SvgValues.MEET);
    }

    double scaleWidth;
    double scaleHeight;
    if (align.toLowerCase() == SvgValues.NONE.toLowerCase()) {
      scaleWidth = currentViewPort.getWidth() / viewBox.getWidth();
      scaleHeight = currentViewPort.getHeight() / viewBox.getHeight();
    } else {
      double scale =
          _getScaleWidthHeight(viewBox, currentViewPort, meetOrSlice);
      scaleWidth = scale;
      scaleHeight = scale;
    }

    CraftRectangle appliedViewBox = CraftRectangle(
        viewBox.getX(),
        viewBox.getY(),
        viewBox.getWidth() * scaleWidth,
        viewBox.getHeight() * scaleHeight);

    double minXOffset =
        currentViewPort.getX() - (appliedViewBox.getX() * scaleWidth);
    double minYOffset =
        currentViewPort.getY() - (appliedViewBox.getY() * scaleHeight);
    double midXOffset = currentViewPort.getX() +
        (currentViewPort.getWidth() / 2) -
        ((appliedViewBox.getX() * scaleWidth) +
            (appliedViewBox.getWidth() / 2));
    double midYOffset = currentViewPort.getY() +
        (currentViewPort.getHeight() / 2) -
        ((appliedViewBox.getY() * scaleHeight) +
            (appliedViewBox.getHeight() / 2));
    double maxXOffset = currentViewPort.getX() +
        currentViewPort.getWidth() -
        ((appliedViewBox.getX() * scaleWidth) + appliedViewBox.getWidth());
    double maxYOffset = currentViewPort.getY() +
        currentViewPort.getHeight() -
        ((appliedViewBox.getY() * scaleHeight) + appliedViewBox.getHeight());

    double xOffset;
    double yOffset;
    String lowerAlign = align.toLowerCase();
    if (lowerAlign == SvgValues.NONE || lowerAlign == SvgValues.XMIN_YMIN) {
      xOffset = minXOffset;
      yOffset = minYOffset;
    } else if (lowerAlign == SvgValues.XMIN_YMID) {
      xOffset = minXOffset;
      yOffset = midYOffset;
    } else if (lowerAlign == SvgValues.XMIN_YMAX) {
      xOffset = minXOffset;
      yOffset = maxYOffset;
    } else if (lowerAlign == SvgValues.XMID_YMIN) {
      xOffset = midXOffset;
      yOffset = minYOffset;
    } else if (lowerAlign == SvgValues.XMID_YMAX) {
      xOffset = midXOffset;
      yOffset = maxYOffset;
    } else if (lowerAlign == SvgValues.XMAX_YMIN) {
      xOffset = maxXOffset;
      yOffset = minYOffset;
    } else if (lowerAlign == SvgValues.XMAX_YMID) {
      xOffset = maxXOffset;
      yOffset = midYOffset;
    } else if (lowerAlign == SvgValues.XMAX_YMAX) {
      xOffset = maxXOffset;
      yOffset = maxYOffset;
    } else if (lowerAlign == SvgValues.XMID_YMID) {
      xOffset = midXOffset;
      yOffset = midYOffset;
    } else {
      return applyViewBox(
          viewBox, currentViewPort, SvgValues.XMID_YMID, SvgValues.MEET);
    }

    appliedViewBox.moveRight(xOffset);
    appliedViewBox.moveUp(yOffset);
    appliedViewBox.setX(appliedViewBox.getX() * scaleWidth);
    appliedViewBox.setY(appliedViewBox.getY() * scaleHeight);
    return appliedViewBox;
  }

  static double _getScaleWidthHeight(CraftRectangle viewBox,
      CraftRectangle currentViewPort, String? meetOrSlice) {
    double scaleWidth = currentViewPort.getWidth() / viewBox.getWidth();
    double scaleHeight = currentViewPort.getHeight() / viewBox.getHeight();
    if (meetOrSlice?.toLowerCase() == SvgValues.SLICE.toLowerCase()) {
      return math.max(scaleWidth, scaleHeight);
    } else {
      if (meetOrSlice == null ||
          meetOrSlice.toLowerCase() == SvgValues.MEET.toLowerCase()) {
        return math.min(scaleWidth, scaleHeight);
      } else {
        throw StateError(CraftSvgExceptionMessageConstant
            .MEET_OR_SLICE_ARGUMENT_IS_INCORRECT);
      }
    }
  }
}
