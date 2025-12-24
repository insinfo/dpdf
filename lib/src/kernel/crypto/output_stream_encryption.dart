import 'dart:typed_data';

/// Base class for output stream encryption.
/// In Dart, we use it as a wrapper that can write to another sink or builder.
abstract class OutputStreamEncryption {
  /// The underlying output (could be a Sink, BytesBuilder, etc.)
  final dynamic output;

  OutputStreamEncryption(this.output);

  /// Writes encrypted data.
  void write(Uint8List b, [int off = 0, int? len]);

  /// Finishes the encryption process (e.g. padding).
  void finish();
}
