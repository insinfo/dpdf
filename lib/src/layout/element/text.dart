import 'package:dpdf/src/layout/element/abstract_element.dart';
import 'package:dpdf/src/layout/element/i_leaf_element.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/renderer/text_renderer.dart';
import 'dart:math' as math;

class Text extends AbstractElement<Text> implements ILeafElement {
  String text;

  Text(this.text);

  String getText() {
    return text;
  }

  void setText(String text) {
    this.text = text;
  }

  @override
  IRenderer makeNewRenderer() {
    return TextRenderer(this, text);
  }

  Text setTextRise(double textRise) {
    setProperty(Property.TEXT_RISE, textRise);
    return this;
  }

  Text setHorizontalScaling(double scaling) {
    setProperty(Property.HORIZONTAL_SCALING, scaling);
    return this;
  }

  Text setSkew(double alpha, double beta) {
    // alpha and beta in degrees
    double alphaRad = math.tan(alpha * math.pi / 180);
    double betaRad = math.tan(beta * math.pi / 180);
    setProperty(Property.SKEW, [alphaRad, betaRad]); // Store as list/array
    return this;
  }
}
