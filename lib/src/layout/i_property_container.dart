abstract class IPropertyContainer {
  bool hasProperty(int property);

  bool hasOwnProperty(int property);

  T? getProperty<T>(int property);

  T? getOwnProperty<T>(int property);

  T? getDefaultProperty<T>(int property);

  void setProperty(int property, Object? value);

  void deleteOwnProperty(int property);
}
