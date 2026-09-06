import 'dart:typed_data';

import 'pdf_version.dart';
import 'encryption_constants.dart';

/// Compression level constants for PDF streams.
class CraftCompressionConstants {
  /// Default compression level (corresponds to deflate default)
  static const int defaultCompression = -1;

  /// No compression
  static const int noCompression = 0;

  /// Best speed compression
  static const int bestSpeed = 1;

  /// Best compression
  static const int bestCompression = 9;

  CraftCompressionConstants._();
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
class CraftWriterProperties {
  /// Compression level for streams.
  int compressionLevel = CraftCompressionConstants.defaultCompression;

  /// Enables object streams for compact serialization.
  bool? isFullCompression;

  /// Indicates if the writer copies objects in smart mode.
  /// If true, PdfDictionary and PdfStream will be hashed and reused
  /// if there's an object with the same content later.
  bool smartMode = false;

  /// Whether to add XMP metadata.
  bool addXmpMetadata = false;

  /// The PDF version to use.
  CraftPdfVersion? pdfVersion;

  /// The ID entry that represents the initial identifier.
  // TODO: Add PdfString support when encryption is implemented
  String? initialDocumentId;

  /// The ID entry that represents a change in a document.
  String? modifiedDocumentId;

  // Encryption properties
  Uint8List? userPassword;
  Uint8List? ownerPassword;
  int permissions = 0;
  int encryptionAlgorithm = CraftEncryptionConstants.standardEncryption40;
  bool isStandardEncryptionUsed = false;

  /// Creates default writer properties.
  CraftWriterProperties();

  /// Defines PDF version for the created document. Default is PDF_1_7.
  CraftWriterProperties setPdfVersion(CraftPdfVersion version) {
    pdfVersion = version;
    return this;
  }

  /// Enables smart mode.
  ///
  /// In smart mode, when resources (such as fonts, images,...) are
  /// encountered, a reference to these resources is saved in a cache,
  /// so that they can be reused. This requires more memory but reduces
  /// the file size of the resulting PDF document.
  CraftWriterProperties useSmartMode() {
    smartMode = true;
    return this;
  }

  /// If true, default XMP metadata based on PdfDocumentInfo will be added.
  /// PDF 2.0 output requires metadata to be included.
  CraftWriterProperties addXmpMetadataFlag() {
    addXmpMetadata = true;
    return this;
  }

  /// Defines the level of compression for the document.
  /// See [CompressionConstants] for available values.
  CraftWriterProperties setCompressionLevel(int level) {
    compressionLevel = level;
    return this;
  }

  /// Defines if full compression mode is enabled.
  ///
  /// If enabled, not only the content of the PDF document will be compressed,
  /// but also the PDF document inner structure (using object streams).
  CraftWriterProperties setFullCompressionMode(bool fullCompressionMode) {
    isFullCompression = fullCompressionMode;
    return this;
  }

  /// Sets the initial document ID.
  ///
  /// The document identifier consists of an initial and a revision value.
  /// The first one (initial id) represents the initial document id.
  /// It's a permanent identifier based on the contents of the file at the time
  /// it was originally created and does not change on incremental updates.
  CraftWriterProperties setInitialDocumentId(String id) {
    initialDocumentId = id;
    return this;
  }

  /// Sets the modified document ID.
  ///
  /// The document identifier consists of an initial and a revision value.
  /// The second one (modified id) should be the same entry,
  /// unless the document has been modified.
  CraftWriterProperties setModifiedDocumentId(String id) {
    modifiedDocumentId = id;
    return this;
  }

  /// Sets standard encryption.
  CraftWriterProperties setStandardEncryption(Uint8List? userPassword,
      Uint8List? ownerPassword, int permissions, int encryptionAlgorithm) {
    this.userPassword = userPassword;
    this.ownerPassword = ownerPassword;
    this.permissions = permissions;
    this.encryptionAlgorithm = encryptionAlgorithm;
    isStandardEncryptionUsed = true;
    return this;
  }
}
