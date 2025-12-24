import 'pdf_version.dart';

/// Compression level constants for PDF streams.
class CompressionConstants {
  /// Default compression level (corresponds to deflate default)
  static const int defaultCompression = -1;

  /// No compression
  static const int noCompression = 0;

  /// Best speed compression
  static const int bestSpeed = 1;

  /// Best compression
  static const int bestCompression = 9;

  CompressionConstants._();
}

/// Properties for configuring PDF document writing.
///
/// Use this class to configure various options when creating PDF documents,
/// such as:
/// - PDF version
/// - Compression settings
/// - Smart mode for resource reuse
/// - XMP metadata options
/// - Document identifiers
///
/// Example:
/// ```dart
/// final properties = WriterProperties()
///   .setPdfVersion(PdfVersion.pdf_1_7)
///   .setFullCompressionMode(true)
///   .useSmartMode();
/// ```
class WriterProperties {
  /// Compression level for streams.
  int compressionLevel = CompressionConstants.defaultCompression;

  /// Indicates if to use full compression (using object streams).
  bool? isFullCompression;

  /// Indicates if the writer copies objects in smart mode.
  /// If true, PdfDictionary and PdfStream will be hashed and reused
  /// if there's an object with the same content later.
  bool smartMode = false;

  /// Whether to add XMP metadata.
  bool addXmpMetadata = false;

  /// The PDF version to use.
  PdfVersion? pdfVersion;

  /// The ID entry that represents the initial identifier.
  // TODO: Add PdfString support when encryption is implemented
  String? initialDocumentId;

  /// The ID entry that represents a change in a document.
  String? modifiedDocumentId;

  /// Creates default writer properties.
  WriterProperties();

  /// Defines PDF version for the created document. Default is PDF_1_7.
  WriterProperties setPdfVersion(PdfVersion version) {
    pdfVersion = version;
    return this;
  }

  /// Enables smart mode.
  ///
  /// In smart mode, when resources (such as fonts, images,...) are
  /// encountered, a reference to these resources is saved in a cache,
  /// so that they can be reused. This requires more memory but reduces
  /// the file size of the resulting PDF document.
  WriterProperties useSmartMode() {
    smartMode = true;
    return this;
  }

  /// If true, default XMP metadata based on PdfDocumentInfo will be added.
  /// For PDF 2.0 documents, metadata will be added in any case.
  WriterProperties addXmpMetadataFlag() {
    addXmpMetadata = true;
    return this;
  }

  /// Defines the level of compression for the document.
  /// See [CompressionConstants] for available values.
  WriterProperties setCompressionLevel(int level) {
    compressionLevel = level;
    return this;
  }

  /// Defines if full compression mode is enabled.
  ///
  /// If enabled, not only the content of the PDF document will be compressed,
  /// but also the PDF document inner structure (using object streams).
  WriterProperties setFullCompressionMode(bool fullCompressionMode) {
    isFullCompression = fullCompressionMode;
    return this;
  }

  /// Sets the initial document ID.
  ///
  /// The /ID entry of a document contains an array with two entries.
  /// The first one (initial id) represents the initial document id.
  /// It's a permanent identifier based on the contents of the file at the time
  /// it was originally created and does not change on incremental updates.
  WriterProperties setInitialDocumentId(String id) {
    initialDocumentId = id;
    return this;
  }

  /// Sets the modified document ID.
  ///
  /// The /ID entry of a document contains an array with two entries.
  /// The second one (modified id) should be the same entry,
  /// unless the document has been modified.
  WriterProperties setModifiedDocumentId(String id) {
    modifiedDocumentId = id;
    return this;
  }

  // TODO: Add encryption support (SetStandardEncryption, SetPublicKeyEncryption)
  // when crypto module is implemented
}
