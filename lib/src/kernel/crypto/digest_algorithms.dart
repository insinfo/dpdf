import 'package:pdfcraft/src/commons/digest/message_digest.dart';
import 'package:pdfcraft/src/commons/digest/sdk_message_digest.dart';
import 'package:pdfcraft/src/kernel/crypto/oid.dart';

/// Digest algorithm identifier registry.
class CraftDigestAlgorithms {
  CraftDigestAlgorithms._();

  static const String sha1 = "SHA-1";
  static const String sha256 = "SHA-256";
  static const String sha384 = "SHA-384";
  static const String sha512 = "SHA-512";
  static const String ripemd160 = "RIPEMD160";
  static const String sha3_256 = "SHA3-256";
  static const String sha3_512 = "SHA3-512";
  static const String sha3_384 = "SHA3-384";
  static const String shake256 = "SHAKE256";

  static const Map<String, String> _digestNames = {
    "1.2.840.113549.2.5": "MD5",
    "1.2.840.113549.2.2": "MD2",
    "1.3.14.3.2.26": "SHA1",
    CraftOID.sha224: "SHA224",
    CraftOID.sha256: "SHA256",
    CraftOID.sha384: "SHA384",
    CraftOID.sha512: "SHA512",
    "1.3.36.3.2.2": "RIPEMD128",
    "1.3.36.3.2.1": "RIPEMD160",
    "1.3.36.3.2.3": "RIPEMD256",
    "1.2.840.113549.1.1.4": "MD5",
    "1.2.840.113549.1.1.2": "MD2",
    "1.2.840.113549.1.1.5": "SHA1",
    "1.2.840.113549.1.1.14": "SHA224",
    "1.2.840.113549.1.1.11": "SHA256",
    "1.2.840.113549.1.1.12": "SHA384",
    "1.2.840.113549.1.1.13": "SHA512",
    "1.2.840.10040.4.3": "SHA1",
    "2.16.840.1.101.3.4.3.1": "SHA224",
    "2.16.840.1.101.3.4.3.2": "SHA256",
    "2.16.840.1.101.3.4.3.3": "SHA384",
    "2.16.840.1.101.3.4.3.4": "SHA512",
    "1.3.36.3.3.1.3": "RIPEMD128",
    "1.3.36.3.3.1.2": "RIPEMD160",
    "1.3.36.3.3.1.4": "RIPEMD256",
    "1.2.643.2.2.9": "GOST3411",
    CraftOID.sha3_224: "SHA3-224",
    CraftOID.sha3_256: "SHA3-256",
    CraftOID.sha3_384: "SHA3-384",
    CraftOID.sha3_512: "SHA3-512",
    CraftOID.shake256: "SHAKE256",
  };

  // Names and output sizes describe the algorithms, independently of a backend.
  static const _profiles = <String, (String, int)>{
    'MD2': ('MD2', 128),
    'MD5': ('MD5', 128),
    'SHA1': ('SHA-1', 160),
    'SHA224': ('SHA-224', 224),
    'SHA256': ('SHA-256', 256),
    'SHA384': ('SHA-384', 384),
    'SHA512': ('SHA-512', 512),
    'RIPEMD128': ('RIPEMD-128', 128),
    'RIPEMD160': ('RIPEMD-160', 160),
    'RIPEMD256': ('RIPEMD-256', 256),
    'SHA3224': ('SHA3-224', 224),
    'SHA3256': ('SHA3-256', 256),
    'SHA3384': ('SHA3-384', 384),
    'SHA3512': ('SHA3-512', 512),
    'SHAKE128': ('SHAKE128', 256),
    'SHAKE256': ('SHAKE256', 512),
  };

  static String _key(String name) =>
      name.toUpperCase().replaceAll(RegExp(r'[-/]'), '');

  static MessageDigest getMessageDigest(String hashAlgorithm) {
    final profile = _profiles[_key(hashAlgorithm)];
    if (profile == null) {
      throw ArgumentError.value(hashAlgorithm, 'hashAlgorithm',
          'No local implementation is registered for this digest.');
    }
    return SdkMessageDigest(profile.$1);
  }

  /// Gets the digest name for a certain id.
  static String getDigest(String oid) {
    return _digestNames[oid] ?? oid;
  }

  /// Returns the digest output size, measured in bits.
  static int getOutputBitLength(String name) {
    return _profiles[_key(name)]?.$2 ?? 0;
  }
}
