import 'package:test/test.dart';

import 'package:dpdf/src/layout/style.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/properties/vertical_alignment.dart';

void main() {
  group('Style Tests', () {
    test('SetAndGetMarginsTest', () {
      double expectedMarginTop = 92;
      double expectedMarginRight = 90;
      double expectedMarginBottom = 86;
      double expectedMarginLeft = 88;
      CraftStyle style = CraftStyle();
      expect(style.getProperty(CraftProperty.MARGIN_TOP), isNull);
      expect(style.getProperty(CraftProperty.MARGIN_RIGHT), isNull);
      expect(style.getProperty(CraftProperty.MARGIN_BOTTOM), isNull);
      expect(style.getProperty(CraftProperty.MARGIN_LEFT), isNull);

      style.setMargins(expectedMarginTop, expectedMarginRight,
          expectedMarginBottom, expectedMarginLeft);

      expect(style.getProperty(CraftProperty.MARGIN_TOP),
          equals(CraftUnitValue.createPointValue(expectedMarginTop)));
      expect(style.getProperty(CraftProperty.MARGIN_RIGHT),
          equals(CraftUnitValue.createPointValue(expectedMarginRight)));
      expect(style.getProperty(CraftProperty.MARGIN_BOTTOM),
          equals(CraftUnitValue.createPointValue(expectedMarginBottom)));
      expect(style.getProperty(CraftProperty.MARGIN_LEFT),
          equals(CraftUnitValue.createPointValue(expectedMarginLeft)));
    });

    test('SetMarginTest', () {
      double expectedMargin = 90;
      CraftStyle style = CraftStyle();
      style.setMargin(expectedMargin);
      expect(style.getProperty(CraftProperty.MARGIN_TOP),
          equals(CraftUnitValue.createPointValue(expectedMargin)));
      expect(style.getProperty(CraftProperty.MARGIN_RIGHT),
          equals(CraftUnitValue.createPointValue(expectedMargin)));
      expect(style.getProperty(CraftProperty.MARGIN_BOTTOM),
          equals(CraftUnitValue.createPointValue(expectedMargin)));
      expect(style.getProperty(CraftProperty.MARGIN_LEFT),
          equals(CraftUnitValue.createPointValue(expectedMargin)));
    });

    test('SetPaddingsTest', () {
      double expPaddingTop = 10;
      double expPaddingRight = 8;
      double expPaddingBottom = 5;
      double expPaddingLeft = 6;
      CraftStyle style = CraftStyle();
      expect(style.getProperty(CraftProperty.PADDING_TOP), isNull);

      style.setPaddings(
          expPaddingTop, expPaddingRight, expPaddingBottom, expPaddingLeft);

      expect(style.getProperty(CraftProperty.PADDING_LEFT),
          equals(CraftUnitValue.createPointValue(expPaddingLeft)));
      expect(style.getProperty(CraftProperty.PADDING_BOTTOM),
          equals(CraftUnitValue.createPointValue(expPaddingBottom)));
      expect(style.getProperty(CraftProperty.PADDING_TOP),
          equals(CraftUnitValue.createPointValue(expPaddingTop)));
      expect(style.getProperty(CraftProperty.PADDING_RIGHT),
          equals(CraftUnitValue.createPointValue(expPaddingRight)));
    });

    test('SetVerticalAlignmentMiddleTest', () {
      CraftVerticalAlignment expectedAlignment = CraftVerticalAlignment.middle;
      CraftStyle style = CraftStyle();
      expect(style.getProperty(CraftProperty.VERTICAL_ALIGNMENT), isNull);
      style.setVerticalAlignment(expectedAlignment);
      expect(style.getProperty(CraftProperty.VERTICAL_ALIGNMENT),
          equals(expectedAlignment));
    });

    test('SetSpacingRatioTest', () {
      double expectedSpacingRatio = 0.5;
      CraftStyle style = CraftStyle();
      expect(style.getProperty(CraftProperty.SPACING_RATIO), isNull);
      style.setSpacingRatio(expectedSpacingRatio);
      expect(style.getProperty(CraftProperty.SPACING_RATIO),
          closeTo(expectedSpacingRatio, 0.0001));
    });

    test('SetKeepTogetherTrueTest', () {
      CraftStyle style = CraftStyle();
      expect(style.getProperty(CraftProperty.KEEP_TOGETHER), isNull);
      style.setKeepTogether(true);
      expect(style.getProperty(CraftProperty.KEEP_TOGETHER), isTrue);
    });

    test('SetRotationAngleTest', () {
      double expectedRotationAngle = 20.0;
      CraftStyle style = CraftStyle();
      expect(style.getProperty(CraftProperty.ROTATION_ANGLE), isNull);
      style.setRotationAngle(expectedRotationAngle);
      expect(style.getProperty(CraftProperty.ROTATION_ANGLE),
          closeTo(expectedRotationAngle, 0.0001));
    });

    test('SetAndGetWidthTest', () {
      double expectedWidth = 100;
      CraftStyle style = CraftStyle();
      expect(style.getProperty(CraftProperty.WIDTH), isNull);
      style.setWidth(expectedWidth);
      expect(style.getProperty(CraftProperty.WIDTH),
          equals(CraftUnitValue.createPointValue(expectedWidth)));
    });

    test('SetMaxHeightTest', () {
      double expectedMaxHeight = 80;
      CraftStyle style = CraftStyle();
      expect(style.getProperty(CraftProperty.MAX_HEIGHT), isNull);
      style.setMaxHeight(expectedMaxHeight);
      expect(style.getProperty(CraftProperty.MAX_HEIGHT),
          equals(CraftUnitValue.createPointValue(expectedMaxHeight)));
    });
  });
}
