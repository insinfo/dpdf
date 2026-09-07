import 'dart:typed_data';

import 'package:dpdf/src/commons/utils/encoding_util.dart';
import 'package:dpdf/src/commons/utils/system_util.dart';
import 'package:dpdf/src/kernel/crypto/arcfour_encryption.dart';

/// An initialization vector generator for a CBC block encryption.
class CraftIVGenerator {
  static final CraftARCFOUREncryption _arcfour = _initArcfour();

  CraftIVGenerator._();

  static CraftARCFOUREncryption _initArcfour() {
    final arcfour = CraftARCFOUREncryption();
    final time = CraftSystemUtil.getTimeBasedSeed();
    final mem = CraftSystemUtil.getFreeMemory();
    final s = "$time+$mem";
    arcfour
        .prepareARCFOURKey(CraftEncodingUtil.convertToBytes(s, "ISO-8859-1"));
    return arcfour;
  }

  /// Gets a 16 byte random initialization vector.
  static Uint8List getIV() {
    return getIVLen(16);
  }

  /// Gets a random initialization vector.
  static Uint8List getIVLen(int len) {
    final b = Uint8List(len);
    // In Dart, we don't need lock for simple single-threaded execution,
    // but if we were multi-threaded we'd need synchronization.
    // For now, simple implementation.
    _arcfour.encryptARCFOURInPlace(b);
    return b;
  }
}
