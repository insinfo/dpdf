/// Base class for document properties.
///
/// Contains common properties for document processing.
class CraftDocumentProperties {
  /// Dependencies for the document.
  dynamic dependencies;

  /// Default constructor.
  CraftDocumentProperties();

  /// Copy constructor.
  CraftDocumentProperties.copy(CraftDocumentProperties other) {
    dependencies = other.dependencies;
  }
}
