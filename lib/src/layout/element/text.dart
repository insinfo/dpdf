import 'package:dpdf/src/layout/element/abstract_element.dart';
import 'package:dpdf/src/layout/element/leaf_content.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/renderer/text_renderer.dart';
import 'dart:math' as math;

class CraftText extends CraftAbstractElement<CraftText>
    implements CraftLeafContent {
  String text;

  CraftText(this.text);

  String getText() {
    return text;
  }

  void setText(String text) {
    this.text = text;
  }

  @override
  CraftRenderer makeNewRenderer() {
    return CraftTextRenderer(this, text);
  }

  CraftText setTextRise(double textRise) {
    setProperty(CraftProperty.TEXT_RISE, textRise);
    return this;
  }

  CraftText setHorizontalScaling(double scaling) {
    setProperty(CraftProperty.HORIZONTAL_SCALING, scaling);
    return this;
  }

  CraftText setSkew(double alpha, double beta) {
    // alpha and beta in degrees
    double alphaRad = math.tan(alpha * math.pi / 180);
    double betaRad = math.tan(beta * math.pi / 180);
    setProperty(CraftProperty.SKEW, [alphaRad, betaRad]); // Store as list/array
    return this;
  }
}
