import 'package:itext/src/layout/i_property_container.dart';
import 'package:itext/src/layout/properties/property.dart';
import 'package:itext/src/layout/properties/unit_value.dart';

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
    return null; // TODO: Implement defaults
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

  T setWidth(double width) {
    setProperty(Property.WIDTH, UnitValue.createPointValue(width));
    return this as T;
  }

  T setHeight(double height) {
    setProperty(Property.HEIGHT, UnitValue.createPointValue(height));
    return this as T;
  }
}
