import 'dart:typed_data';

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
  /// The password for encrypted documents.
  Uint8List? password;

  /// Maximum memory to use for decompressed streams.
  /// Set to null for no limit (default).
  int? memoryLimit;

  /// Creates default reader properties.
  ReaderProperties();

  /// Creates a copy of another ReaderProperties.
  ReaderProperties.from(ReaderProperties other)
      : password =
            other.password != null ? Uint8List.fromList(other.password!) : null,
        memoryLimit = other.memoryLimit;

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

  void _clearEncryptionParams() {
    password = null;
    // TODO: Clear certificate params when public key encryption is implemented
  }

  // TODO: Add public key security params when crypto module is implemented
  // setPublicKeySecurityParams(IX509Certificate certificate, IPrivateKey key)
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
