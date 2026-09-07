import 'dart:typed_data';

import 'package:dpdf/src/commons/digest/message_digest.dart';
import 'package:dpdf/src/kernel/crypto/digest_algorithms.dart';
import 'package:dpdf/src/kernel/crypto/decryptor.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_encryption.dart';

/// Base class for security handlers.
abstract class CraftSecurityHandler {
  /// The global encryption key
  Uint8List mkey = Uint8List(0);

  /// The encryption key for a particular object/generation.
  Uint8List? nextObjectKey;

  /// Key size associated with the object and generation.
  int nextObjectKeySize = 0;

  late MessageDigest md5;

  /// Work area to prepare the object/generation bytes
  final Uint8List extra = Uint8List(5);

  CraftSecurityHandler() {
    _initMd5MessageDigest();
  }

  /// Calculates encryption key for particular object individually based in its object/generation.
  void setHashKeyForNextObject(int objNumber, int objGeneration) {
    md5.reset();
    extra[0] = objNumber & 0xFF;
    extra[1] = (objNumber >> 8) & 0xFF;
    extra[2] = (objNumber >> 16) & 0xFF;
    extra[3] = objGeneration & 0xFF;
    extra[4] = (objGeneration >> 8) & 0xFF;

    md5.updateAll(mkey);
    md5.updateAll(extra);

    nextObjectKey = md5.digest();
    nextObjectKeySize = mkey.length + 5;
    if (nextObjectKeySize > 16) {
      nextObjectKeySize = 16;
    }
  }

  /// Gets a stream wrapper, responsible for encryption.
  CraftOutputStreamEncryption getEncryptionStream(dynamic os);

  /// Gets decryptor object.
  CraftDecryptor getDecryptor();

  /// Gets encryption key for a particular object/generation.
  Uint8List getNextObjectKey() {
    return Uint8List.fromList(nextObjectKey ?? []);
  }

  /// Gets global encryption key.
  Uint8List getMkey() {
    return Uint8List.fromList(mkey);
  }

  /// Init md5 message digest.
  void _initMd5MessageDigest() {
    md5 = CraftDigestAlgorithms.getMessageDigest("MD5");
  }
}
