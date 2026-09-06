import 'package:dpdf/src/layout/i_property_container.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/properties/vertical_alignment.dart';
import 'package:dpdf/src/layout/properties/text_alignment.dart';
import 'package:dpdf/src/layout/properties/horizontal_alignment.dart';
import 'package:dpdf/src/layout/properties/layout_position.dart';
import 'package:dpdf/src/kernel/colors/device_gray.dart';

abstract class ElementPropertyContainer<T extends IPropertyContainer>
    implements IPropertyContainer {
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
    if (property == Property.FONT_SIZE) {
      return UnitValue.createPointValue(12.0) as D;
    } else if (property == Property.FONT_COLOR) {
      return DeviceGray.BLACK as D;
    } else if (property == Property.STROKE_COLOR) {
      return DeviceGray.BLACK as D;
    }
    return null;
  }

  @override
  void setProperty(int property, Object? value) {
    properties[property] = value;
  }

  // Fluent setters
  T setFontSize(double fontSize) {
    setProperty(Property.FONT_SIZE, UnitValue.createPointValue(fontSize));
    return this as T;
  }

  T setFont(Object? font) {
    setProperty(Property.FONT, font);
    return this as T;
  }

  T setWidth(double width) {
    setProperty(Property.WIDTH, UnitValue.createPointValue(width));
    return this as T;
  }

  T setHeight(double height) {
    setProperty(Property.HEIGHT, UnitValue.createPointValue(height));
    return this as T;
  }

  T setMarginTop(double margin) {
    setProperty(Property.MARGIN_TOP, UnitValue.createPointValue(margin));
    return this as T;
  }

  T setMarginBottom(double margin) {
    setProperty(Property.MARGIN_BOTTOM, UnitValue.createPointValue(margin));
    return this as T;
  }

  T setMarginLeft(double margin) {
    setProperty(Property.MARGIN_LEFT, UnitValue.createPointValue(margin));
    return this as T;
  }

  T setMarginRight(double margin) {
    setProperty(Property.MARGIN_RIGHT, UnitValue.createPointValue(margin));
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
    setProperty(Property.PADDING_TOP, UnitValue.createPointValue(padding));
    return this as T;
  }

  T setPaddingBottom(double padding) {
    setProperty(Property.PADDING_BOTTOM, UnitValue.createPointValue(padding));
    return this as T;
  }

  T setPaddingLeft(double padding) {
    setProperty(Property.PADDING_LEFT, UnitValue.createPointValue(padding));
    return this as T;
  }

  T setPaddingRight(double padding) {
    setProperty(Property.PADDING_RIGHT, UnitValue.createPointValue(padding));
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

  T setVerticalAlignment(VerticalAlignment alignment) {
    setProperty(Property.VERTICAL_ALIGNMENT, alignment);
    return this as T;
  }

  T setSpacingRatio(double ratio) {
    setProperty(Property.SPACING_RATIO, ratio);
    return this as T;
  }

  T setKeepTogether(bool keepTogether) {
    setProperty(Property.KEEP_TOGETHER, keepTogether);
    return this as T;
  }

  T setRotationAngle(double angle) {
    setProperty(Property.ROTATION_ANGLE, angle);
    return this as T;
  }

  T setMaxHeight(double height) {
    setProperty(Property.MAX_HEIGHT, UnitValue.createPointValue(height));
    return this as T;
  }

  T setMinHeight(double height) {
    setProperty(Property.MIN_HEIGHT, UnitValue.createPointValue(height));
    return this as T;
  }

  T setMaxWidth(double width) {
    setProperty(Property.MAX_WIDTH, UnitValue.createPointValue(width));
    return this as T;
  }

  T setMinWidth(double width) {
    setProperty(Property.MIN_WIDTH, UnitValue.createPointValue(width));
    return this as T;
  }

  T setTextAlignment(TextAlignment alignment) {
    setProperty(Property.TEXT_ALIGNMENT, alignment);
    return this as T;
  }

  T setHorizontalAlignment(HorizontalAlignment alignment) {
    setProperty(Property.HORIZONTAL_ALIGNMENT, alignment);
    return this as T;
  }

  T setFixedPosition(int pageNumber, double left, double bottom, double width) {
    setProperty(Property.PAGE_NUMBER, pageNumber);
    return setFixedPositionInternal(left, bottom, width);
  }

  T setFixedPositionInternal(double left, double bottom, double width) {
    setProperty(Property.LEFT, UnitValue.createPointValue(left));
    setProperty(Property.BOTTOM, UnitValue.createPointValue(bottom));
    setProperty(Property.WIDTH, UnitValue.createPointValue(width));
    setProperty(Property.POSITION, LayoutPosition.FIXED);
    return this as T;
  }
}
