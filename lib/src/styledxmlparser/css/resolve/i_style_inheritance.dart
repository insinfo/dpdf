/// Interface for attribute and style-inheritance logic
abstract class IStyleInheritance {
  /// Checks if a property or attribute is inheritable.
  ///
  /// [propertyIdentifier] the identifier for property
  /// returns true, if the property is inheritable, false otherwise
  bool isInheritable(String propertyIdentifier);
}
