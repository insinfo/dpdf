import 'document_properties.dart';

/// Class with additional properties for [PdfDocument] processing in stamping mode.
///
/// Needs to be passed at document initialization.
/// See [PageFlushingHelper] documentation to find more information about modes
/// of document processing.
class CraftStampingProperties extends CraftDocumentProperties {
  bool _appendMode = false;
  bool _preserveEncryption = false;
  bool _disableMac = false;

  /// Default constructor, use provided setters for configuration options.
  CraftStampingProperties();

  /// Creates a copy of class instance.
  CraftStampingProperties.copy(CraftStampingProperties other)
      : super.copy(other) {
    _appendMode = other._appendMode;
    _preserveEncryption = other._preserveEncryption;
    _disableMac = other._disableMac;
  }

  /// Creates a copy of [DocumentProperties] instance.
  CraftStampingProperties.fromDocumentProperties(
      CraftDocumentProperties documentProperties)
      : super.copy(documentProperties);

  /// Defines if the document will be edited in append mode.
  ///
  /// In append mode, changes are added incrementally to the end of the PDF file,
  /// preserving the original content. This is essential for multiple signatures.
  ///
  /// Returns this [StampingProperties] instance for fluent API.
  CraftStampingProperties useAppendMode() {
    _appendMode = true;
    return this;
  }

  /// Defines if the encryption of the original document (if it was encrypted)
  /// will be preserved.
  ///
  /// Output encryption is not retained unless explicitly requested.
  ///
  /// Returns this [StampingProperties] instance for fluent API.
  CraftStampingProperties preserveEncryption() {
    _preserveEncryption = true;
    return this;
  }

  /// Disables MAC token in the output PDF-2.0 document.
  ///
  /// By default, MAC token will be embedded.
  /// This property does not remove MAC token from existing document in append mode
  /// because it removes MAC protection from all previous revisions also.
  ///
  /// Returns this [StampingProperties] instance for fluent API.
  CraftStampingProperties disableMac() {
    _disableMac = true;
    return this;
  }

  /// Returns whether append mode is enabled.
  bool usesIncrementalRevision() => _appendMode;

  /// Returns whether encryption preservation is enabled.
  bool isPreserveEncryption() => _preserveEncryption;

  /// Returns whether MAC is disabled.
  bool isDisableMac() => _disableMac;
}
