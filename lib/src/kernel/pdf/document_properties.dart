/// Base class for document properties.
///
/// Contains common properties for document processing.
class DocumentProperties {
  /// Dependencies for the document.
  dynamic dependencies;

  /// Default constructor.
  DocumentProperties();

  /// Copy constructor.
  DocumentProperties.copy(DocumentProperties other) {
    dependencies = other.dependencies;
  }
}
