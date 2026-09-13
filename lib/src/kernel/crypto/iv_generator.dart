import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dpdf/src/commons/utils/encoding_util.dart';
import 'package:dpdf/src/commons/utils/system_util.dart';
import 'package:dpdf/src/kernel/crypto/arcfour_encryption.dart';

/// Random material for the encryption algorithms of ISO 32000-1:2008, 7.6.
///
/// "Algorithm 1" requires the AES initialisation vector to be "a 16-byte
/// random number", and the AES-256 handler draws its file encryption key, its
/// salts and the padding of the `/Perms` string from the same source, so the
/// generator uses the platform cryptographic random number generator. A
/// deterministic RC4 stream keyed from the clock is kept only as a fallback
/// for platforms that refuse to provide one.
class IVGenerator {
  static final math.Random? _secure = _openSecureRandom();
  static final ARCFOUREncryption _arcfour = _initArcfour();

  IVGenerator._();

  static math.Random? _openSecureRandom() {
    try {
      return math.Random.secure();
    } catch (_) {
      return null;
    }
  }

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

  /// Gets [len] random bytes.
  static Uint8List getIVLen(int len) {
    final b = Uint8List(len);
    final secure = _secure;
    if (secure != null) {
      for (var i = 0; i < len; i++) {
        b[i] = secure.nextInt(256);
      }
      return b;
    }
    _arcfour.encryptARCFOURInPlace(b);
    return b;
  }
}
