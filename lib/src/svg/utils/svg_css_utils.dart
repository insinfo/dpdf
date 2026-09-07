import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_dimension_parsing_utils.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_types_validation_utils.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

class CraftSvgCssUtils {
  CraftSvgCssUtils._();

  static List<String> splitValueList(String? value) {
    if (value == null || value.isEmpty) {
      return [];
    }
    value = value.trim();
    // Split by comma or any whitespace character
    final regex = RegExp(r'[, \t\n\r\f]+');
    return value.split(regex).where((s) => s.isNotEmpty).toList();
  }

  static double parseAbsoluteLength(
      CraftAbstractSvgNodeRenderer svgNodeRenderer,
      String length,
      double percentBaseValue,
      double defaultValue,
      CraftSvgDrawContext context) {
    double em = svgNodeRenderer.getCurrentFontSize(context);
    double rem = context.getCssContext().getRootFontSize();
    return CraftCssDimensionParsingUtils.parseLength(
        length, percentBaseValue, defaultValue, em, rem);
  }

  static double parseAbsoluteVerticalLength(
      CraftAbstractSvgNodeRenderer svgNodeRenderer,
      String length,
      double defaultValue,
      CraftSvgDrawContext context) {
    double percentBaseValue = _calculatePercentBaseValueIfNeeded(
        svgNodeRenderer, context, length, false);
    return parseAbsoluteLength(
        svgNodeRenderer, length, percentBaseValue, defaultValue, context);
  }

  static double parseAbsoluteHorizontalLength(
      CraftAbstractSvgNodeRenderer svgNodeRenderer,
      String length,
      double defaultValue,
      CraftSvgDrawContext context) {
    double percentBaseValue = _calculatePercentBaseValueIfNeeded(
        svgNodeRenderer, context, length, true);
    return parseAbsoluteLength(
        svgNodeRenderer, length, percentBaseValue, defaultValue, context);
  }

  static List<double>? parseViewBox(CraftSvgNodeRenderer svgRenderer) {
    String? vbString =
        svgRenderer.getAttribute(CraftSvgConstants.Attributes.VIEWBOX);
    if (vbString == null) {
      vbString = svgRenderer
          .getAttribute(CraftSvgConstants.Attributes.VIEWBOX.toLowerCase());
    }

    if (vbString == null) return null;

    List<String> valueStrings = splitValueList(vbString);
    List<double> doubleValues = [];
    for (String s in valueStrings) {
      doubleValues.add(CraftCssDimensionParsingUtils.parseAbsoluteLength(s));
    }

    if (doubleValues.length != CraftSvgConstants.Values.VIEWBOX_VALUES_NUMBER) {
      // logger warning: SvgLogMessageConstant.VIEWBOX_VALUE_MUST_BE_FOUR_NUMBERS
      return null;
    }

    if (doubleValues[2] < 0 || doubleValues[3] < 0) {
      // logger warning: SvgLogMessageConstant.VIEWBOX_WIDTH_AND_HEIGHT_CANNOT_BE_NEGATIVE
      return null;
    }

    return doubleValues;
  }

  static CraftRectangle extractWidthAndHeight(CraftSvgNodeRenderer svgRenderer,
      double em, CraftSvgDrawContext context) {
    double percentHorizontalBase;
    double percentVerticalBase;

    CraftRectangle? customViewport = context.getCustomViewport();
    if (customViewport == null) {
      List<double>? viewBox = parseViewBox(svgRenderer);
      if (viewBox == null) {
        percentHorizontalBase = CraftSvgConstants.Values.DEFAULT_VIEWPORT_WIDTH;
        percentVerticalBase = CraftSvgConstants.Values.DEFAULT_VIEWPORT_HEIGHT;
      } else {
        percentHorizontalBase = viewBox[2];
        percentVerticalBase = viewBox[3];
      }
    } else {
      percentHorizontalBase = customViewport.getWidth();
      percentVerticalBase = customViewport.getHeight();
    }

    double rem = context.getCssContext().getRootFontSize();
    String? widthStr =
        svgRenderer.getAttribute(CraftSvgConstants.Attributes.WIDTH);
    double finalWidth = _calculateFinalSvgRendererLength(
        widthStr, em, rem, percentHorizontalBase);

    String? heightStr =
        svgRenderer.getAttribute(CraftSvgConstants.Attributes.HEIGHT);
    double finalHeight = _calculateFinalSvgRendererLength(
        heightStr, em, rem, percentVerticalBase);

    return CraftRectangle(0, 0, finalWidth, finalHeight);
  }

  static double _calculateFinalSvgRendererLength(
      String? length, double em, double rem, double percentBase) {
    final l = length ?? CraftSvgConstants.Values.DEFAULT_WIDTH_AND_HEIGHT_VALUE;

    if (CraftCssTypesValidationUtils.isRemValue(l)) {
      return CraftCssDimensionParsingUtils.parseRelativeValue(l, rem);
    } else if (CraftCssTypesValidationUtils.isEmValue(l)) {
      return CraftCssDimensionParsingUtils.parseRelativeValue(l, em);
    } else if (CraftCssTypesValidationUtils.isPercentageValue(l)) {
      return CraftCssDimensionParsingUtils.parseRelativeValue(l, percentBase);
    } else {
      return CraftCssDimensionParsingUtils.parseAbsoluteLength(l);
    }
  }

  static double _calculatePercentBaseValueIfNeeded(
      CraftAbstractSvgNodeRenderer svgNodeRenderer,
      CraftSvgDrawContext context,
      String length,
      bool isXAxis) {
    double percentBaseValue = 0.0;
    if (CraftCssTypesValidationUtils.isPercentageValue(length)) {
      final viewBox = svgNodeRenderer.getCurrentViewBox(context);
      percentBaseValue = isXAxis ? viewBox.getWidth() : viewBox.getHeight();
    }
    return percentBaseValue;
  }
}
