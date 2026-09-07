import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/colors/device_gray.dart';

/// This class represents text and tspan SVG elements properties identifying their graphics state.
class SvgTextProperties {
  Color? fillColor = DeviceGray.BLACK;
  Color? strokeColor = DeviceGray.BLACK;
  double fillOpacity = 1.0;
  double strokeOpacity = 1.0;
  List<double>? dashArray;
  double dashPhase = 0.0;
  double lineWidth = 1.0;
  List<dynamic> textDecoration = []; // Placeholder for Underline

  SvgTextProperties();

  SvgTextProperties.copy(SvgTextProperties other) {
    fillColor = other.fillColor;
    strokeColor = other.strokeColor;
    fillOpacity = other.fillOpacity;
    strokeOpacity = other.strokeOpacity;
    dashArray = other.dashArray != null ? List.from(other.dashArray!) : null;
    dashPhase = other.dashPhase;
    lineWidth = other.lineWidth;
    textDecoration = List.from(other.textDecoration);
  }

  Color? getFillColor() => fillColor;
  SvgTextProperties setFillColor(Color? color) {
    fillColor = color;
    return this;
  }

  Color? getStrokeColor() => strokeColor;
  SvgTextProperties setStrokeColor(Color? color) {
    strokeColor = color;
    return this;
  }

  double getFillOpacity() => fillOpacity;
  SvgTextProperties setFillOpacity(double opacity) {
    fillOpacity = opacity;
    return this;
  }

  double getStrokeOpacity() => strokeOpacity;
  SvgTextProperties setStrokeOpacity(double opacity) {
    strokeOpacity = opacity;
    return this;
  }

  double getLineWidth() => lineWidth;
  SvgTextProperties setLineWidth(double width) {
    lineWidth = width;
    return this;
  }

  List<double>? getDashArray() => dashArray;
  double getDashPhase() => dashPhase;
  SvgTextProperties setDashPattern(List<double>? array, double phase) {
    dashArray = array;
    dashPhase = phase;
    return this;
  }

  List<dynamic> getTextDecoration() => textDecoration;
  SvgTextProperties setTextDecoration(List<dynamic> list) {
    textDecoration = list;
    return this;
  }
}
