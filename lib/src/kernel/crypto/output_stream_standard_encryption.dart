import 'dart:math';
import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/arcfour_encryption.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_encryption.dart';

/// Standard encryption output stream (RC4).
class OutputStreamStandardEncryption extends OutputStreamEncryption {
  late ARCFOUREncryption _arcfour;

  OutputStreamStandardEncryption(dynamic output, Uint8List key,
      [int off = 0, int? len])
      : super(output) {
    _arcfour = ARCFOUREncryption();
    _arcfour.prepareARCFOURKey(key, off, len);
  }

  @override
  void write(Uint8List b, [int off = 0, int? len]) {
    var length = len ?? (b.length - off);
    final bufferSize = min(length, 4192);
    final b2 = Uint8List(bufferSize);

    while (length > 0) {
      final sz = min(length, b2.length);
      _arcfour.encryptARCFOUR(b, off, sz, b2, 0);

      // In Dart, we write to the underlying output which can be a Sink or BytesBuilder
      if (output is Sink<List<int>>) {
        output.add(b2.sublist(0, sz));
      } else if (output is BytesBuilder) {
        output.add(b2.sublist(0, sz));
      } else {
        // Fallback or generic write (if we support more types)
        throw Exception(
            "Unsupported output type for OutputStreamStandardEncryption");
      }

      length -= sz;
      off += sz;
    }
  }

  @override
  void finish() {
    // RC4 doesn't need finishing
  }
}
