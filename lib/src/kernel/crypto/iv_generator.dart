import 'dart:typed_data';

import 'package:dpdf/src/commons/utils/encoding_util.dart';
import 'package:dpdf/src/commons/utils/system_util.dart';
import 'package:dpdf/src/kernel/crypto/arcfour_encryption.dart';

/// An initialization vector generator for a CBC block encryption.
class IVGenerator {
  static final ARCFOUREncryption _arcfour = _initArcfour();

  IVGenerator._();

  static ARCFOUREncryption _initArcfour() {
    final arcfour = ARCFOUREncryption();
    final time = SystemUtil.getTimeBasedSeed();
    final mem = SystemUtil.getFreeMemory();
    final s = "$time+$mem";
    arcfour.prepareARCFOURKey(EncodingUtil.convertToBytes(s, "ISO-8859-1"));
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
