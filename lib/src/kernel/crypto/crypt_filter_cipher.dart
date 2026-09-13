import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/aes_cipher.dart';
import 'package:dpdf/src/kernel/crypto/aes_decryptor.dart';
import 'package:dpdf/src/kernel/crypto/arcfour_encryption.dart';
import 'package:dpdf/src/kernel/crypto/crypt_filter.dart';
import 'package:dpdf/src/kernel/crypto/decryptor.dart';
import 'package:dpdf/src/kernel/crypto/digest_algorithms.dart';
import 'package:dpdf/src/kernel/crypto/iv_generator.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_aes_encryption.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_encryption.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_standard_encryption.dart';
import 'package:dpdf/src/kernel/crypto/standard_decryptor.dart';

/// Applies "Algorithm 1: Encryption of data using the RC4 or AES algorithms"
/// of ISO 32000-1:2008, 7.6.2, for one crypt filter.
///
/// The file encryption key comes from the security handler; this class only
/// knows how to turn it into a per-object key and how to run the symmetric
/// cipher named by the filter's `/CFM` entry.
class CryptFilterCipher {
  /// The four bytes appended to the key of an AES crypt filter, step (b):
  /// "the value `sAlT`, which corresponds to the hexadecimal values 0x73,
  /// 0x41, 0x6C, 0x54".
  static final Uint8List aesSalt = Uint8List.fromList([0x73, 0x41, 0x6c, 0x54]);

  /// The filter this cipher implements.
  final CryptFilter filter;

  /// The file encryption key computed by the security handler.
  final Uint8List fileKey;

  CryptFilterCipher(this.filter, Uint8List fileKey)
      : fileKey = Uint8List.fromList(fileKey);

  /// Whether the data passes through untouched.
  ///
  /// `Identity` is defined by Table 26; `None` directs the stream to the
  /// security handler, which for a handler that performs no private
  /// transformation of its own likewise leaves the bytes alone.
  bool get isPassThrough =>
      filter.method == CryptFilterMethod.identity ||
      filter.method == CryptFilterMethod.none;

  /// Computes the object key of "Algorithm 1", steps (b) to (d).
  ///
  /// AESV3 keys are used as is: ISO 32000-2 drops the per-object derivation
  /// because the 256-bit file key already is unique per document.
  Uint8List objectKey(int objectNumber, int generation) {
    if (filter.method == CryptFilterMethod.aesV3) {
      return Uint8List.fromList(fileKey);
    }
    final md5 = DigestAlgorithms.getMessageDigest('MD5');
    final extra = Uint8List(5);
    extra[0] = objectNumber & 0xFF;
    extra[1] = (objectNumber >> 8) & 0xFF;
    extra[2] = (objectNumber >> 16) & 0xFF;
    extra[3] = generation & 0xFF;
    extra[4] = (generation >> 8) & 0xFF;
    md5.updateAll(fileKey);
    md5.updateAll(extra);
    if (filter.method == CryptFilterMethod.aesV2) {
      md5.updateAll(aesSalt);
    }
    final digest = md5.digest();
    var size = fileKey.length + 5;
    if (size > 16) size = 16;
    return Uint8List.fromList(digest.sublist(0, size));
  }

  /// The number of key bytes "Algorithm 1" step (d) hands to the cipher.
  int objectKeySize() {
    if (filter.method == CryptFilterMethod.aesV3) return fileKey.length;
    final size = fileKey.length + 5;
    return size > 16 ? 16 : size;
  }

  /// Encrypts [data] for the indirect object [objectNumber] [generation].
  Uint8List encrypt(Uint8List data, int objectNumber, int generation) {
    if (isPassThrough) return Uint8List.fromList(data);
    final key = objectKey(objectNumber, generation);
    return encryptWithKey(data, key);
  }

  /// Decrypts [data] for the indirect object [objectNumber] [generation].
  Uint8List decrypt(Uint8List data, int objectNumber, int generation) {
    if (isPassThrough) return Uint8List.fromList(data);
    final key = objectKey(objectNumber, generation);
    return decryptWithKey(data, key);
  }

  /// Encrypts [data] with an explicit key, bypassing "Algorithm 1".
  ///
  /// 7.4.10 states that a stream naming a crypt filter is decrypted "using the
  /// key as is", which is how public-key crypt filters carrying their own
  /// `/Recipients` entry work.
  Uint8List encryptWithKey(Uint8List data, Uint8List key) {
    if (isPassThrough) return Uint8List.fromList(data);
    if (filter.method == CryptFilterMethod.v2) {
      final out = Uint8List(data.length);
      ARCFOUREncryption()
        ..prepareARCFOURKey(key)
        ..encryptARCFOUR(data, 0, data.length, out, 0);
      return out;
    }
    // AESV2 and AESV3: CBC mode with a random 16-byte initialisation vector
    // stored as the first 16 bytes of the encrypted stream or string, and the
    // RFC 2898 padding scheme described in 7.6.2.
    final iv = IVGenerator.getIV();
    final cipher = AESCipher(true, key, iv);
    final body = cipher.update(data, 0, data.length);
    final tail = cipher.doFinal();
    final result = Uint8List(iv.length + body.length + tail.length);
    result.setRange(0, iv.length, iv);
    result.setRange(iv.length, iv.length + body.length, body);
    result.setRange(iv.length + body.length, result.length, tail);
    return result;
  }

  /// Decrypts [data] with an explicit key, bypassing "Algorithm 1".
  Uint8List decryptWithKey(Uint8List data, Uint8List key) {
    if (isPassThrough) return Uint8List.fromList(data);
    if (filter.method == CryptFilterMethod.v2) {
      final out = Uint8List(data.length);
      ARCFOUREncryption()
        ..prepareARCFOURKey(key)
        ..encryptARCFOUR(data, 0, data.length, out, 0);
      return out;
    }
    if (data.length < 16) {
      // An AES payload always carries at least the initialisation vector.
      return Uint8List(0);
    }
    final decryptor = AesDecryptor(key, 0, key.length);
    final head = decryptor.update(data, 0, data.length) ?? Uint8List(0);
    final tail = decryptor.finish() ?? Uint8List(0);
    final result = Uint8List(head.length + tail.length);
    result.setRange(0, head.length, head);
    result.setRange(head.length, result.length, tail);
    return result;
  }

  /// The streaming encryptor used by the writer for stream payloads.
  OutputStreamEncryption encryptionStream(
      dynamic output, int objectNumber, int generation) {
    final key = objectKey(objectNumber, generation);
    if (filter.method == CryptFilterMethod.v2) {
      return OutputStreamStandardEncryption(output, key, 0, key.length);
    }
    return OutputStreamAesEncryption(output, key, 0, key.length);
  }

  /// The streaming decryptor used by the reader for stream payloads.
  Decryptor decryptor(int objectNumber, int generation) {
    final key = objectKey(objectNumber, generation);
    if (filter.method == CryptFilterMethod.v2) {
      return StandardDecryptor(key, 0, key.length);
    }
    return AesDecryptor(key, 0, key.length);
  }
}
