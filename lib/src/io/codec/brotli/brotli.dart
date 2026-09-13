import 'dart:typed_data';

import 'brotli_input_stream.dart';
import 'brotli_runtime_exception.dart';
import 'state.dart';

/// Brotli decompression (RFC 7932).
///
/// Only decoding is bundled. The one caller inside this package is the WOFF 2.0
/// reader, which needs to expand a font's table data, and a font file is never
/// written back as WOFF 2.0.
abstract final class Brotli {
  /// Expands [data], which must be a complete Brotli stream.
  ///
  /// [maxOutputBytes] bounds the result: a Brotli stream a few bytes long can
  /// legitimately expand to gigabytes, so a caller reading an untrusted font
  /// needs a ceiling it chooses itself rather than an allocation failure.
  ///
  /// Throws [BrotliDecodeException] when the stream is malformed or when it
  /// would grow past [maxOutputBytes].
  static Uint8List decode(Uint8List data, {int maxOutputBytes = 1 << 28}) {
    if (maxOutputBytes <= 0) {
      throw ArgumentError.value(
          maxOutputBytes, 'maxOutputBytes', 'must be positive');
    }
    final input = BrotliInputStream(ByteArrayInputStream(data));
    final output = BytesBuilder(copy: false);
    final buffer = Uint8List(64 * 1024);
    try {
      while (true) {
        final read = input.read(buffer, 0, buffer.length);
        if (read < 0) break;
        if (read == 0) continue;
        if (output.length + read > maxOutputBytes) {
          throw BrotliDecodeException(
              'The Brotli stream expands past the $maxOutputBytes byte limit.');
        }
        output.add(Uint8List.sublistView(buffer, 0, read));
      }
    } on BrotliDecodeException {
      rethrow;
    } on BrotliRuntimeException catch (error) {
      throw BrotliDecodeException(error.toString());
    } on RangeError catch (error) {
      throw BrotliDecodeException(
          'The Brotli stream reads outside its bounds: ${error.message}');
    } on StateError catch (error) {
      throw BrotliDecodeException(error.message);
    } finally {
      input.close();
    }
    return output.takeBytes();
  }
}

/// A Brotli stream this decoder will not read.
class BrotliDecodeException implements Exception {
  final String message;

  const BrotliDecodeException(this.message);

  @override
  String toString() => 'BrotliDecodeException: $message';
}
