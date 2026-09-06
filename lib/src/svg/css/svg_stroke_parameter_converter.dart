import 'package:dpdf/src/styledxmlparser/css/util/css_dimension_parsing_utils.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_coordinate_utils.dart';
import 'package:dpdf/src/svg/utils/svg_css_utils.dart';
import 'package:collection/collection.dart';

/// This class converts stroke related SVG parameters and attributes into those from PDF specification.
class SvgStrokeParameterConverter {
  SvgStrokeParameterConverter._();

  /// Convert stroke related SVG parameters and attributes into PDF line dash parameters.
  static PdfLineDashParameters? convertStrokeDashParameters(
      String? strokeDashArray,
      String? strokeDashOffset,
      double fontSize,
      SvgDrawContext context) {
    if (strokeDashArray != null &&
        strokeDashArray.toLowerCase() != SvgConstants.Values.NONE) {
      double rem = context.getCssContext().getRootFontSize();
      double percentBaseValue =
          SvgCoordinateUtils.calculateNormalizedDiagonalLength(context);
      List<String> dashArrayStrings =
          SvgCssUtils.splitValueList(strokeDashArray);

      if (dashArrayStrings.isNotEmpty) {
        if (dashArrayStrings.length % 2 == 1) {
          // If an odd number of values is provided, then the list of values is repeated to yield an even
          // number of values. Thus, 5,3,2 is equivalent to 5,3,2,5,3,2.
          dashArrayStrings.addAll(List<String>.from(dashArrayStrings));
        }

        List<double> dashArrayData = [];
        for (String s in dashArrayStrings) {
          dashArrayData.add(CssDimensionParsingUtils.parseLength(
              s, percentBaseValue, 1.0, fontSize, rem));
        }

        // Parse stroke dash offset
        double dashPhase = 0.0;
        if (strokeDashOffset != null &&
            strokeDashOffset.isNotEmpty &&
            strokeDashOffset.toLowerCase() != SvgConstants.Values.NONE) {
          dashPhase = CssDimensionParsingUtils.parseLength(
              strokeDashOffset, percentBaseValue, 1.0, fontSize, rem);
        }

        return PdfLineDashParameters(dashArrayData, dashPhase);
      }
    }
    return null;
  }
}

/// This class represents PDF dash parameters.
class PdfLineDashParameters {
  final List<double> dashArray;
  final double dashPhase;

  /// Construct PDF dash parameters.
  PdfLineDashParameters(this.dashArray, this.dashPhase);

  /// Return dash array.
  List<double> getDashArray() => dashArray;

  /// Return dash phase.
  double getDashPhase() => dashPhase;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfLineDashParameters) return false;
    return dashPhase == other.dashPhase &&
        const ListEquality().equals(dashArray, other.dashArray);
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(dashArray), dashPhase);
}
