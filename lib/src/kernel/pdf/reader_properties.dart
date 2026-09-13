import 'dart:typed_data';

import 'package:dpdf/src/pki/rsa.dart';
import 'package:dpdf/src/sign/x509_certificate.dart';

/// Optional recovery when the declared cross-reference sections cannot be read.
enum PdfRecoveryMode { strict, scan, skipStreams }

/// Properties for configuring PDF document reading.
///
/// Use this class to configure various options when reading PDF documents,
/// such as:
/// - Decryption password for encrypted PDFs
/// - Memory limits for handling large documents
///
/// Example:
/// ```dart
/// final properties = ReaderProperties()
///   .setPassword(utf8.encode('secretPassword'));
/// ```
class ReaderProperties {
  /// Opt-in bounded file cache for PdfReader.fromFile on the VM.
  bool readFileInBlocks = false;

  /// Files at least this large are read through the bounded block cache even
  /// when [readFileInBlocks] was not explicitly enabled. Set to `null` to
  /// preserve the legacy always-materialize behaviour.
  int? largeFileBlockThreshold = 64 * 1024 * 1024;
  int fileBlockSize = 262144;
  int fileCacheBlocks = 32;
  PdfRecoveryMode recoveryMode = PdfRecoveryMode.strict;

  /// Maximum input bytes examined by recovery (default 4 GiB).
  ///
  /// Recovery remains opt-in through [recoveryMode]. The larger default lets
  /// `skipStreams` repair multi-gigabyte scans while object and decompression
  /// limits continue to bound allocations.
  int recoveryScanLimit = 4 * 1024 * 1024 * 1024;

  /// Bounds object identifiers and recovered object count.
  int recoveryObjectLimit = 1000000;

  /// The password for encrypted documents.
  Uint8List? password;

  /// The certificate that identifies the reader among the recipients of a
  /// document encrypted by a public-key security handler
  /// (ISO 32000-1:2008, 7.6.4).
  X509Certificate? certificate;

  /// The private key matching [certificate], used to unwrap the content
  /// encryption key of the PKCS#7 enveloped data.
  RSAPrivateKey? certificateKey;

  /// Maximum memory to use for decompressed streams.
  /// Set to null for no limit (default).
  int? memoryLimit;

  /// Creates default reader properties.
  ReaderProperties();

  /// Creates a copy of another ReaderProperties.
  ReaderProperties.from(ReaderProperties other)
      : readFileInBlocks = other.readFileInBlocks,
        largeFileBlockThreshold = other.largeFileBlockThreshold,
        fileBlockSize = other.fileBlockSize,
        fileCacheBlocks = other.fileCacheBlocks,
        password =
            other.password != null ? Uint8List.fromList(other.password!) : null,
        certificate = other.certificate,
        certificateKey = other.certificateKey,
        memoryLimit = other.memoryLimit,
        recoveryMode = other.recoveryMode,
        recoveryScanLimit = other.recoveryScanLimit,
        recoveryObjectLimit = other.recoveryObjectLimit;

  /// Defines the password for encrypted documents.
  ///
  /// This could be either user or owner password.
  ///
  /// [password] - The password to use to open the document.
  ReaderProperties setPassword(Uint8List password) {
    _clearEncryptionParams();
    this.password = password;
    return this;
  }

  /// Sets the password from a string (using UTF-8 encoding).
  ReaderProperties setPasswordFromString(String password) {
    return setPassword(Uint8List.fromList(password.codeUnits));
  }

  /// Sets the maximum memory limit for handling decompressed streams.
  ///
  /// This helps prevent out-of-memory errors when processing large PDFs.
  /// Set to null for no limit.
  ReaderProperties setMemoryLimit(int? limit) {
    memoryLimit = limit;
    return this;
  }

  /// Defines the recipient credentials for documents encrypted with a
  /// public-key security handler (ISO 32000-1:2008, 7.6.4).
  ///
  /// The reader scans the `/Recipients` list for an enveloped data object
  /// addressed to [certificate] and unwraps the content encryption key with
  /// [privateKey].
  ReaderProperties setPublicKeySecurityParams(
      X509Certificate certificate, RSAPrivateKey privateKey) {
    _clearEncryptionParams();
    this.certificate = certificate;
    certificateKey = privateKey;
    return this;
  }

  void _clearEncryptionParams() {
    password = null;
    certificate = null;
    certificateKey = null;
  }
}

/// Handler for memory limits during PDF processing.
///
/// This class is used to track memory usage during decompression
/// and other memory-intensive operations.
class MemoryLimitsAwareHandler {
  /// Maximum memory to allocate in bytes.
  final int maxMemory;

  /// Current memory usage in bytes.
  int _currentMemory = 0;

  /// Creates a memory limits handler with the specified max memory.
  MemoryLimitsAwareHandler(this.maxMemory);

  /// Creates a new instance (for copy operations).
  MemoryLimitsAwareHandler createNewInstance() {
    return MemoryLimitsAwareHandler(maxMemory);
  }

  /// Checks if allocation is within limits and tracks it.
  ///
  /// Throws an exception if allocation would exceed limits.
  void checkAndAllocate(int bytes) {
    if (_currentMemory + bytes > maxMemory) {
      throw StateError('Memory limit exceeded: tried to allocate $bytes bytes, '
          'already using $_currentMemory of $maxMemory bytes');
    }
    _currentMemory += bytes;
  }

  /// Releases previously allocated memory.
  void release(int bytes) {
    _currentMemory -= bytes;
    if (_currentMemory < 0) _currentMemory = 0;
  }

  /// Gets current memory usage.
  int get currentMemory => _currentMemory;

  /// Resets memory tracking.
  void reset() {
    _currentMemory = 0;
  }
}
