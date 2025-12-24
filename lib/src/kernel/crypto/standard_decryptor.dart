import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/arcfour_encryption.dart';
import 'package:dpdf/src/kernel/crypto/i_decryptor.dart';

/// Standard decryptor implementation (RC4).
class StandardDecryptor implements IDecryptor {
  late ARCFOUREncryption _arcfour;

  StandardDecryptor(Uint8List key, [int off = 0, int? len]) {
    _arcfour = ARCFOUREncryption();
    _arcfour.prepareARCFOURKey(key, off, len);
  }

  @override
  Uint8List update(Uint8List b, int off, int len) {
    final b2 = Uint8List(len);
    _arcfour.encryptARCFOUR(b, off, len, b2, 0);
    return b2;
  }

  @override
  Uint8List? finish() {
    return null;
  }
}
