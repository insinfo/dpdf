import 'package:dpdf/src/commons/digest/i_message_digest.dart';
import 'package:dpdf/src/commons/digest/pointy_castle_digest.dart';
import 'package:dpdf/src/kernel/crypto/oid.dart';

/// Class that contains a map with the different message digest algorithms.
class DigestAlgorithms {
  DigestAlgorithms._();

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
    OID.sha224: "SHA224",
    OID.sha256: "SHA256",
    OID.sha384: "SHA384",
    OID.sha512: "SHA512",
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
    OID.sha3_224: "SHA3-224",
    OID.sha3_256: "SHA3-256",
    OID.sha3_384: "SHA3-384",
    OID.sha3_512: "SHA3-512",
    OID.shake256: "SHAKE256",
  };

  static const Map<String, int> _bitLengths = {
    "MD2": 128,
    "MD-2": 128,
    "MD5": 128,
    "MD-5": 128,
    "SHA1": 160,
    "SHA-1": 160,
    "SHA224": 224,
    "SHA-224": 224,
    "SHA256": 256,
    "SHA-256": 256,
    "SHA384": 384,
    "SHA-384": 384,
    "SHA512": 512,
    "SHA-512": 512,
    "RIPEMD128": 128,
    "RIPEMD-128": 128,
    "RIPEMD160": 160,
    "RIPEMD-160": 160,
    "RIPEMD256": 256,
    "RIPEMD-256": 256,
    "SHA3-224": 224,
    "SHA3-256": 256,
    "SHA3-384": 384,
    "SHA3-512": 512,
    "SHAKE256": 512,
  };

  /// Creates a MessageDigest object that can be used to create a hash.
  static IMessageDigest getMessageDigest(String hashAlgorithm) {
    // PointyCastle algorithm names are slightly different or need normalization
    var alg = hashAlgorithm.toUpperCase().replaceAll("-", "");
    if (alg == "SHA1") alg = "SHA-1";
    if (alg == "SHA224") alg = "SHA-224";
    if (alg == "SHA256") alg = "SHA-256";
    if (alg == "SHA384") alg = "SHA-384";
    if (alg == "SHA512") alg = "SHA-512";
    if (alg == "MD5") alg = "MD5";
    if (alg == "MD2") alg = "MD2";

    // TODO: Add more mappings as needed
    return PointyCastleDigest(alg);
  }

  /// Gets the digest name for a certain id.
  static String getDigest(String oid) {
    return _digestNames[oid] ?? oid;
  }

  /// Retrieve the output length in bits of the given digest algorithm.
  static int getOutputBitLength(String name) {
    return _bitLengths[name.toUpperCase()] ?? 0;
  }
}
