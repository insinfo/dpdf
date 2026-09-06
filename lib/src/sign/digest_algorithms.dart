import 'dart:typed_data';

import 'i_external_digest.dart';
import 'oid.dart';
import 'crypto_digest.dart';

/// Class that contains a map with the different message digest algorithms.
class DigestAlgorithms {
  DigestAlgorithms._();

  /// Algorithm available for signatures since PDF 1.3.
  static const String sha1 = 'SHA-1';

  /// Algorithm available for signatures since PDF 1.6.
  static const String sha256 = 'SHA-256';

  /// Algorithm available for signatures since PDF 1.7.
  static const String sha384 = 'SHA-384';

  /// Algorithm available for signatures since PDF 1.7.
  static const String sha512 = 'SHA-512';

  /// Algorithm available for signatures since PDF 1.7.
  static const String ripemd160 = 'RIPEMD160';

  /// Algorithm available for signatures since PDF 2.0 extended by ISO/TS 32001.
  static const String sha3_256 = 'SHA3-256';

  /// Algorithm available for signatures since PDF 2.0 extended by ISO/TS 32001.
  static const String sha3_512 = 'SHA3-512';

  /// Algorithm available for signatures since PDF 2.0 extended by ISO/TS 32001.
  static const String sha3_384 = 'SHA3-384';

  /// Algorithm available for signatures since PDF 2.0 extended by ISO/TS 32001.
  /// The output length is fixed at 512 bits (64 bytes).
  static const String shake256 = 'SHAKE256';

  /// Maps the digest IDs with the human-readable name of the digest algorithm.
  static final Map<String, String> _digestNames = {
    '1.2.840.113549.2.5': 'MD5',
    '1.2.840.113549.2.2': 'MD2',
    '1.3.14.3.2.26': 'SHA1',
    OID.sha224: 'SHA224',
    OID.sha256: 'SHA256',
    OID.sha384: 'SHA384',
    OID.sha512: 'SHA512',
    '1.3.36.3.2.2': 'RIPEMD128',
    '1.3.36.3.2.1': 'RIPEMD160',
    '1.3.36.3.2.3': 'RIPEMD256',
    '1.2.840.113549.1.1.4': 'MD5',
    '1.2.840.113549.1.1.2': 'MD2',
    '1.2.840.113549.1.1.5': 'SHA1',
    '1.2.840.113549.1.1.14': 'SHA224',
    '1.2.840.113549.1.1.11': 'SHA256',
    '1.2.840.113549.1.1.12': 'SHA384',
    '1.2.840.113549.1.1.13': 'SHA512',
    '1.2.840.10040.4.3': 'SHA1',
    '2.16.840.1.101.3.4.3.1': 'SHA224',
    '2.16.840.1.101.3.4.3.2': 'SHA256',
    '2.16.840.1.101.3.4.3.3': 'SHA384',
    '2.16.840.1.101.3.4.3.4': 'SHA512',
    '1.3.36.3.3.1.3': 'RIPEMD128',
    '1.3.36.3.3.1.2': 'RIPEMD160',
    '1.3.36.3.3.1.4': 'RIPEMD256',
    '1.2.643.2.2.9': 'GOST3411',
    OID.sha3_224: 'SHA3-224',
    OID.sha3_256: 'SHA3-256',
    OID.sha3_384: 'SHA3-384',
    OID.sha3_512: 'SHA3-512',
  };

  /// Maps the name of a digest algorithm with its ID.
  static final Map<String, String> _allowedDigests = {
    'MD2': '1.2.840.113549.2.2',
    'MD-2': '1.2.840.113549.2.2',
    'MD5': '1.2.840.113549.2.5',
    'MD-5': '1.2.840.113549.2.5',
    'SHA1': '1.3.14.3.2.26',
    'SHA-1': '1.3.14.3.2.26',
    'SHA224': OID.sha224,
    'SHA-224': OID.sha224,
    'SHA256': OID.sha256,
    'SHA-256': OID.sha256,
    'SHA384': OID.sha384,
    'SHA-384': OID.sha384,
    'SHA512': OID.sha512,
    'SHA-512': OID.sha512,
    'RIPEMD128': '1.3.36.3.2.2',
    'RIPEMD-128': '1.3.36.3.2.2',
    'RIPEMD160': '1.3.36.3.2.1',
    'RIPEMD-160': '1.3.36.3.2.1',
    'RIPEMD256': '1.3.36.3.2.3',
    'RIPEMD-256': '1.3.36.3.2.3',
    'GOST3411': '1.2.643.2.2.9',
    'SHA3-224': OID.sha3_224,
    'SHA3-256': OID.sha3_256,
    'SHA3-384': OID.sha3_384,
    'SHA3-512': OID.sha3_512,
  };

  /// Maps algorithm names to output lengths in bits.
  static final Map<String, int> _bitLengths = {
    'MD2': 128,
    'MD-2': 128,
    'MD5': 128,
    'MD-5': 128,
    'SHA1': 160,
    'SHA-1': 160,
    'SHA224': 224,
    'SHA-224': 224,
    'SHA256': 256,
    'SHA-256': 256,
    'SHA384': 384,
    'SHA-384': 384,
    'SHA512': 512,
    'SHA-512': 512,
    'RIPEMD128': 128,
    'RIPEMD-128': 128,
    'RIPEMD160': 160,
    'RIPEMD-160': 160,
    'RIPEMD256': 256,
    'RIPEMD-256': 256,
    'SHA3-224': 224,
    'SHA3-256': 256,
    'SHA3-384': 384,
    'SHA3-512': 512,
    'SHAKE256': 512,
  };

  /// Default digest implementation.
  static const IExternalDigest _defaultDigest = CryptoDigest();

  /// Get a digest algorithm.
  ///
  /// @param digestOid oid of the digest algorithm
  /// @return MessageDigest object
  static IMessageDigest getMessageDigestFromOid(String digestOid) {
    return getMessageDigest(getDigest(digestOid));
  }

  /// Creates a MessageDigest object that can be used to create a hash.
  ///
  /// @param hashAlgorithm the algorithm you want to use to create a hash
  /// @return a MessageDigest object
  static IMessageDigest getMessageDigest(String hashAlgorithm) {
    return _defaultDigest.getMessageDigest(hashAlgorithm);
  }

  /// Creates a hash using a specific digest algorithm.
  ///
  /// @param data the message of which you want to create a hash
  /// @param hashAlgorithm the algorithm used to create the hash
  /// @return the hash
  static Future<Uint8List> digest(
      Stream<List<int>> data, String hashAlgorithm) async {
    final messageDigest = getMessageDigest(hashAlgorithm);
    await for (final chunk in data) {
      messageDigest.update(Uint8List.fromList(chunk));
    }
    return messageDigest.digest();
  }

  /// Create a digest based on the input bytes.
  ///
  /// @param data data to be digested
  /// @param hashAlgorithm algorithm to be used
  /// @return digest of the data
  static Uint8List digestBytes(Uint8List data, String hashAlgorithm) {
    final messageDigest = getMessageDigest(hashAlgorithm);
    messageDigest.update(data);
    return messageDigest.digest();
  }

  /// Gets the digest name for a certain id.
  ///
  /// @param oid an id (for instance "1.2.840.113549.2.5")
  /// @return a digest name (for instance "MD5")
  static String getDigest(String oid) {
    final ret = _digestNames[oid];
    if (ret == null) {
      // Return oid if not found
      return oid;
    }
    return ret;
  }

  /// Returns the id of a digest algorithms that is allowed in PDF,
  /// or null if it isn't allowed.
  ///
  /// @param name the name of the digest algorithm
  /// @return an oid
  static String? getAllowedDigest(String? name) {
    if (name == null) {
      throw ArgumentError('The name of the digest algorithm is null');
    }
    return _allowedDigests[name.toUpperCase()];
  }

  /// Retrieve the output length in bits of the given digest algorithm.
  ///
  /// @param name the name of the digest algorithm
  /// @return the length of the output of the algorithm in bits
  static int getOutputBitLength(String? name) {
    if (name == null) {
      throw ArgumentError('The name of the digest algorithm is null');
    }
    final len = _bitLengths[name];
    if (len == null) {
      throw ArgumentError('Unknown digest algorithm: $name');
    }
    return len;
  }

  /// Normalizes a digest algorithm name to its canonical form.
  ///
  /// @param algorithm the algorithm name
  /// @return normalized algorithm name
  static String normalizeDigestName(String algorithm) {
    final upper = algorithm.toUpperCase().replaceAll('-', '');
    switch (upper) {
      case 'SHA1':
        return sha1;
      case 'SHA256':
        return sha256;
      case 'SHA384':
        return sha384;
      case 'SHA512':
        return sha512;
      default:
        return algorithm;
    }
  }
}
