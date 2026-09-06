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
      Style style = Style();
      expect(style.getProperty(Property.MARGIN_TOP), isNull);
      expect(style.getProperty(Property.MARGIN_RIGHT), isNull);
      expect(style.getProperty(Property.MARGIN_BOTTOM), isNull);
      expect(style.getProperty(Property.MARGIN_LEFT), isNull);

      style.setMargins(expectedMarginTop, expectedMarginRight,
          expectedMarginBottom, expectedMarginLeft);

      expect(style.getProperty(Property.MARGIN_TOP),
          equals(UnitValue.createPointValue(expectedMarginTop)));
      expect(style.getProperty(Property.MARGIN_RIGHT),
          equals(UnitValue.createPointValue(expectedMarginRight)));
      expect(style.getProperty(Property.MARGIN_BOTTOM),
          equals(UnitValue.createPointValue(expectedMarginBottom)));
      expect(style.getProperty(Property.MARGIN_LEFT),
          equals(UnitValue.createPointValue(expectedMarginLeft)));
    });

    test('SetMarginTest', () {
      double expectedMargin = 90;
      Style style = Style();
      style.setMargin(expectedMargin);
      expect(style.getProperty(Property.MARGIN_TOP),
          equals(UnitValue.createPointValue(expectedMargin)));
      expect(style.getProperty(Property.MARGIN_RIGHT),
          equals(UnitValue.createPointValue(expectedMargin)));
      expect(style.getProperty(Property.MARGIN_BOTTOM),
          equals(UnitValue.createPointValue(expectedMargin)));
      expect(style.getProperty(Property.MARGIN_LEFT),
          equals(UnitValue.createPointValue(expectedMargin)));
    });

    test('SetPaddingsTest', () {
      double expPaddingTop = 10;
      double expPaddingRight = 8;
      double expPaddingBottom = 5;
      double expPaddingLeft = 6;
      Style style = Style();
      expect(style.getProperty(Property.PADDING_TOP), isNull);

      style.setPaddings(
          expPaddingTop, expPaddingRight, expPaddingBottom, expPaddingLeft);

      expect(style.getProperty(Property.PADDING_LEFT),
          equals(UnitValue.createPointValue(expPaddingLeft)));
      expect(style.getProperty(Property.PADDING_BOTTOM),
          equals(UnitValue.createPointValue(expPaddingBottom)));
      expect(style.getProperty(Property.PADDING_TOP),
          equals(UnitValue.createPointValue(expPaddingTop)));
      expect(style.getProperty(Property.PADDING_RIGHT),
          equals(UnitValue.createPointValue(expPaddingRight)));
    });

    test('SetVerticalAlignmentMiddleTest', () {
      VerticalAlignment expectedAlignment = VerticalAlignment.middle;
      Style style = Style();
      expect(style.getProperty(Property.VERTICAL_ALIGNMENT), isNull);
      style.setVerticalAlignment(expectedAlignment);
      expect(style.getProperty(Property.VERTICAL_ALIGNMENT),
          equals(expectedAlignment));
    });

    test('SetSpacingRatioTest', () {
      double expectedSpacingRatio = 0.5;
      Style style = Style();
      expect(style.getProperty(Property.SPACING_RATIO), isNull);
      style.setSpacingRatio(expectedSpacingRatio);
      expect(style.getProperty(Property.SPACING_RATIO),
          closeTo(expectedSpacingRatio, 0.0001));
    });

    test('SetKeepTogetherTrueTest', () {
      Style style = Style();
      expect(style.getProperty(Property.KEEP_TOGETHER), isNull);
      style.setKeepTogether(true);
      expect(style.getProperty(Property.KEEP_TOGETHER), isTrue);
    });

    test('SetRotationAngleTest', () {
      double expectedRotationAngle = 20.0;
      Style style = Style();
      expect(style.getProperty(Property.ROTATION_ANGLE), isNull);
      style.setRotationAngle(expectedRotationAngle);
      expect(style.getProperty(Property.ROTATION_ANGLE),
          closeTo(expectedRotationAngle, 0.0001));
    });

    test('SetAndGetWidthTest', () {
      double expectedWidth = 100;
      Style style = Style();
      expect(style.getProperty(Property.WIDTH), isNull);
      style.setWidth(expectedWidth);
      expect(style.getProperty(Property.WIDTH),
          equals(UnitValue.createPointValue(expectedWidth)));
    });

    test('SetMaxHeightTest', () {
      double expectedMaxHeight = 80;
      Style style = Style();
      expect(style.getProperty(Property.MAX_HEIGHT), isNull);
      style.setMaxHeight(expectedMaxHeight);
      expect(style.getProperty(Property.MAX_HEIGHT),
          equals(UnitValue.createPointValue(expectedMaxHeight)));
    });
  });
}
