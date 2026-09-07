import 'package:dpdf/src/layout/property_container.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/properties/vertical_alignment.dart';
import 'package:dpdf/src/layout/properties/text_alignment.dart';
import 'package:dpdf/src/layout/properties/horizontal_alignment.dart';
import 'package:dpdf/src/layout/properties/layout_position.dart';
import 'package:dpdf/src/kernel/colors/device_gray.dart';

abstract class CraftElementPropertyContainer<T extends CraftPropertyContainer>
    implements CraftPropertyContainer {
  final Map<int, Object?> properties = {};

  @override
  bool hasProperty(int property) {
    return hasOwnProperty(property);
  }

  @override
  bool hasOwnProperty(int property) {
    return properties.containsKey(property);
  }

  @override
  void deleteOwnProperty(int property) {
    properties.remove(property);
  }

  @override
  D? getProperty<D>(int property) {
    return getOwnProperty<D>(property);
  }

  @override
  D? getOwnProperty<D>(int property) {
    return properties[property] as D?;
  }

  @override
  D? getDefaultProperty<D>(int property) {
    if (property == CraftProperty.FONT_SIZE) {
      return CraftUnitValue.createPointValue(12.0) as D;
    } else if (property == CraftProperty.FONT_COLOR) {
      return CraftDeviceGray.BLACK as D;
    } else if (property == CraftProperty.STROKE_COLOR) {
      return CraftDeviceGray.BLACK as D;
    }
    return null;
  }

  @override
  void setProperty(int property, Object? value) {
    properties[property] = value;
  }

  // Fluent setters
  T setFontSize(double fontSize) {
    setProperty(
        CraftProperty.FONT_SIZE, CraftUnitValue.createPointValue(fontSize));
    return this as T;
  }

  T setFont(Object? font) {
    setProperty(CraftProperty.FONT, font);
    return this as T;
  }

  T setWidth(double width) {
    setProperty(CraftProperty.WIDTH, CraftUnitValue.createPointValue(width));
    return this as T;
  }

  T setHeight(double height) {
    setProperty(CraftProperty.HEIGHT, CraftUnitValue.createPointValue(height));
    return this as T;
  }

  T setMarginTop(double margin) {
    setProperty(
        CraftProperty.MARGIN_TOP, CraftUnitValue.createPointValue(margin));
    return this as T;
  }

  T setMarginBottom(double margin) {
    setProperty(
        CraftProperty.MARGIN_BOTTOM, CraftUnitValue.createPointValue(margin));
    return this as T;
  }

  T setMarginLeft(double margin) {
    setProperty(
        CraftProperty.MARGIN_LEFT, CraftUnitValue.createPointValue(margin));
    return this as T;
  }

  T setMarginRight(double margin) {
    setProperty(
        CraftProperty.MARGIN_RIGHT, CraftUnitValue.createPointValue(margin));
    return this as T;
  }

  T setMargin(double margin) {
    setMarginTop(margin);
    setMarginBottom(margin);
    setMarginLeft(margin);
    setMarginRight(margin);
    return this as T;
  }

  T setMargins(double top, double right, double bottom, double left) {
    setMarginTop(top);
    setMarginRight(right);
    setMarginBottom(bottom);
    setMarginLeft(left);
    return this as T;
  }

  T setPaddingTop(double padding) {
    setProperty(
        CraftProperty.PADDING_TOP, CraftUnitValue.createPointValue(padding));
    return this as T;
  }

  T setPaddingBottom(double padding) {
    setProperty(
        CraftProperty.PADDING_BOTTOM, CraftUnitValue.createPointValue(padding));
    return this as T;
  }

  T setPaddingLeft(double padding) {
    setProperty(
        CraftProperty.PADDING_LEFT, CraftUnitValue.createPointValue(padding));
    return this as T;
  }

  T setPaddingRight(double padding) {
    setProperty(
        CraftProperty.PADDING_RIGHT, CraftUnitValue.createPointValue(padding));
    return this as T;
  }

  T setPadding(double padding) {
    setPaddingTop(padding);
    setPaddingBottom(padding);
    setPaddingLeft(padding);
    setPaddingRight(padding);
    return this as T;
  }

  T setPaddings(double top, double right, double bottom, double left) {
    setPaddingTop(top);
    setPaddingRight(right);
    setPaddingBottom(bottom);
    setPaddingLeft(left);
    return this as T;
  }

  T setVerticalAlignment(CraftVerticalAlignment alignment) {
    setProperty(CraftProperty.VERTICAL_ALIGNMENT, alignment);
    return this as T;
  }

  T setSpacingRatio(double ratio) {
    setProperty(CraftProperty.SPACING_RATIO, ratio);
    return this as T;
  }

  T setKeepTogether(bool keepTogether) {
    setProperty(CraftProperty.KEEP_TOGETHER, keepTogether);
    return this as T;
  }

  T setRotationAngle(double angle) {
    setProperty(CraftProperty.ROTATION_ANGLE, angle);
    return this as T;
  }

  T setMaxHeight(double height) {
    setProperty(
        CraftProperty.MAX_HEIGHT, CraftUnitValue.createPointValue(height));
    return this as T;
  }

  T setMinHeight(double height) {
    setProperty(
        CraftProperty.MIN_HEIGHT, CraftUnitValue.createPointValue(height));
    return this as T;
  }

  T setMaxWidth(double width) {
    setProperty(
        CraftProperty.MAX_WIDTH, CraftUnitValue.createPointValue(width));
    return this as T;
  }

  T setMinWidth(double width) {
    setProperty(
        CraftProperty.MIN_WIDTH, CraftUnitValue.createPointValue(width));
    return this as T;
  }

  T setTextAlignment(CraftTextAlignment alignment) {
    setProperty(CraftProperty.TEXT_ALIGNMENT, alignment);
    return this as T;
  }

  T setHorizontalAlignment(CraftHorizontalAlignment alignment) {
    setProperty(CraftProperty.HORIZONTAL_ALIGNMENT, alignment);
    return this as T;
  }

  T setFixedPosition(int pageNumber, double left, double bottom, double width) {
    setProperty(CraftProperty.PAGE_NUMBER, pageNumber);
    return setFixedPositionInternal(left, bottom, width);
  }

  T setFixedPositionInternal(double left, double bottom, double width) {
    setProperty(CraftProperty.LEFT, CraftUnitValue.createPointValue(left));
    setProperty(CraftProperty.BOTTOM, CraftUnitValue.createPointValue(bottom));
    setProperty(CraftProperty.WIDTH, CraftUnitValue.createPointValue(width));
    setProperty(CraftProperty.POSITION, CraftLayoutPosition.FIXED);
    return this as T;
  }
}
