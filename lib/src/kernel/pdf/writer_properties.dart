import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/securityhandler/pub_key_security_handler.dart';

import 'compression_constants.dart';
import 'pdf_version.dart';
import 'encryption_constants.dart';

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

  /// Enables object streams for compact serialization.
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
  ///
  /// The value is the raw first element of the trailer `/ID` array; the
  /// standard security handler hashes it in "Algorithm 2", step (e).
  String? initialDocumentId;

  /// The ID entry that represents a change in a document.
  String? modifiedDocumentId;

  // Encryption properties
  Uint8List? userPassword;
  Uint8List? ownerPassword;
  int permissions = 0;
  int encryptionAlgorithm = EncryptionConstants.standardEncryption40;
  bool isStandardEncryptionUsed = false;

  /// The recipient groups of a public-key security handler
  /// (ISO 32000-1:2008, 7.6.4). Each group carries its own permissions.
  List<PublicKeyRecipientGroup>? publicKeyRecipients;
  bool isPublicKeyEncryptionUsed = false;

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
  /// PDF 2.0 output requires metadata to be included.
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
  /// The document identifier consists of an initial and a revision value.
  /// The first one (initial id) represents the initial document id.
  /// It's a permanent identifier based on the contents of the file at the time
  /// it was originally created and does not change on incremental updates.
  WriterProperties setInitialDocumentId(String id) {
    initialDocumentId = id;
    return this;
  }

  /// Sets the modified document ID.
  ///
  /// The document identifier consists of an initial and a revision value.
  /// The second one (modified id) should be the same entry,
  /// unless the document has been modified.
  WriterProperties setModifiedDocumentId(String id) {
    modifiedDocumentId = id;
    return this;
  }

  /// Sets standard encryption.
  WriterProperties setStandardEncryption(Uint8List? userPassword,
      Uint8List? ownerPassword, int permissions, int encryptionAlgorithm) {
    this.userPassword = userPassword;
    this.ownerPassword = ownerPassword;
    this.permissions = permissions;
    this.encryptionAlgorithm = encryptionAlgorithm;
    isStandardEncryptionUsed = true;
    isPublicKeyEncryptionUsed = false;
    publicKeyRecipients = null;
    return this;
  }

  /// Sets public-key encryption for the created document.
  ///
  /// ISO 32000-1:2008, Table 23: "There shall be only one PKCS#7 object per
  /// unique set of access permissions", so every group in [recipients] becomes
  /// one entry of the `/Recipients` array.
  WriterProperties setPublicKeyEncryption(
      List<PublicKeyRecipientGroup> recipients, int encryptionAlgorithm) {
    publicKeyRecipients = recipients;
    this.encryptionAlgorithm = encryptionAlgorithm;
    isPublicKeyEncryptionUsed = true;
    isStandardEncryptionUsed = false;
    userPassword = null;
    ownerPassword = null;
    return this;
  }
}
