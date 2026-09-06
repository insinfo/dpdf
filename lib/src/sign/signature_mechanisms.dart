import 'oid.dart';

/// Bidirectional lookup of signature mechanism identifiers
/// and algorithm names, including selection of an OID
/// for a signing algorithm paired with a digest.
class CraftSignatureMechanisms {
  CraftSignatureMechanisms._();

  /// Maps IDs of signature algorithms with its human-readable name.
  static final Map<String, String> algorithmNames = {
    '1.2.840.113549.1.1.1': 'RSA',
    '1.2.840.10040.4.1': 'DSA',
    '1.2.840.113549.1.1.2': 'RSA',
    '1.2.840.113549.1.1.4': 'RSA',
    '1.2.840.113549.1.1.5': 'RSA',
    '1.2.840.113549.1.1.11': 'RSA',
    '1.2.840.113549.1.1.12': 'RSA',
    '1.2.840.113549.1.1.13': 'RSA',
    '1.2.840.113549.1.1.14': 'RSA',
    '1.2.840.10040.4.3': 'DSA',
    '2.16.840.1.101.3.4.3.1': 'DSA',
    '2.16.840.1.101.3.4.3.2': 'DSA',
    '1.3.14.3.2.29': 'RSA',
    '1.3.36.3.3.1.2': 'RSA',
    '1.3.36.3.3.1.3': 'RSA',
    '1.3.36.3.3.1.4': 'RSA',
    '1.2.643.2.2.19': 'ECGOST3410',
    // Elliptic curve public key cryptography
    '1.2.840.10045.2.1': 'ECDSA',
    // Elliptic curve Digital Signature Algorithm (DSA) coupled with SHA
    '1.2.840.10045.4.1': 'ECDSA',
    // Elliptic curve Digital Signature Algorithm (DSA)
    '1.2.840.10045.4.3': 'ECDSA',
    // ECDSA coupled with SHA256
    '1.2.840.10045.4.3.2': 'ECDSA',
    // ECDSA coupled with SHA384
    '1.2.840.10045.4.3.3': 'ECDSA',
    // ECDSA coupled with SHA512
    '1.2.840.10045.4.3.4': 'ECDSA',
    // SHA-3 signature identifiers registered in the NIST CSOR.
    '2.16.840.1.101.3.4.3.5': 'DSA',
    '2.16.840.1.101.3.4.3.6': 'DSA',
    '2.16.840.1.101.3.4.3.7': 'DSA',
    '2.16.840.1.101.3.4.3.8': 'DSA',
    '2.16.840.1.101.3.4.3.9': 'ECDSA',
    '2.16.840.1.101.3.4.3.10': 'ECDSA',
    '2.16.840.1.101.3.4.3.11': 'ECDSA',
    '2.16.840.1.101.3.4.3.12': 'ECDSA',
    '2.16.840.1.101.3.4.3.13': 'RSA',
    '2.16.840.1.101.3.4.3.14': 'RSA',
    '2.16.840.1.101.3.4.3.15': 'RSA',
    '2.16.840.1.101.3.4.3.16': 'RSA',
    // RSASSA-PSS
    CraftOID.rsassaPss: 'RSASSA-PSS',
    // EdDSA
    CraftOID.ed25519: 'Ed25519',
    CraftOID.ed448: 'Ed448',
  };

  /// Maps digest algorithm names to RSA OIDs.
  static final Map<String, String> rsaOidsByDigest = {
    'SHA224': '1.2.840.113549.1.1.14',
    'SHA256': '1.2.840.113549.1.1.11',
    'SHA384': '1.2.840.113549.1.1.12',
    'SHA512': '1.2.840.113549.1.1.13',
    'SHA-224': '1.2.840.113549.1.1.14',
    'SHA-256': '1.2.840.113549.1.1.11',
    'SHA-384': '1.2.840.113549.1.1.12',
    'SHA-512': '1.2.840.113549.1.1.13',
    'SHA3-224': '2.16.840.1.101.3.4.3.13',
    'SHA3-256': '2.16.840.1.101.3.4.3.14',
    'SHA3-384': '2.16.840.1.101.3.4.3.15',
    'SHA3-512': '2.16.840.1.101.3.4.3.16',
  };

  /// Maps digest algorithm names to DSA OIDs.
  static final Map<String, String> dsaOidsByDigest = {
    'SHA224': '2.16.840.1.101.3.4.3.1',
    'SHA256': '2.16.840.1.101.3.4.3.2',
    'SHA384': '2.16.840.1.101.3.4.3.3',
    'SHA512': '2.16.840.1.101.3.4.3.4',
    'SHA3-224': '2.16.840.1.101.3.4.3.5',
    'SHA3-256': '2.16.840.1.101.3.4.3.6',
    'SHA3-384': '2.16.840.1.101.3.4.3.7',
    'SHA3-512': '2.16.840.1.101.3.4.3.8',
  };

  /// Maps digest algorithm names to ECDSA OIDs.
  static final Map<String, String> ecdsaOidsByDigest = {
    'SHA1': '1.2.840.10045.4.1',
    'SHA224': '1.2.840.10045.4.3.1',
    'SHA256': '1.2.840.10045.4.3.2',
    'SHA384': '1.2.840.10045.4.3.3',
    'SHA512': '1.2.840.10045.4.3.4',
    'SHA3-224': '2.16.840.1.101.3.4.3.9',
    'SHA3-256': '2.16.840.1.101.3.4.3.10',
    'SHA3-384': '2.16.840.1.101.3.4.3.11',
    'SHA3-512': '2.16.840.1.101.3.4.3.12',
  };

  /// Resolves an OID for the requested signing and digest algorithms.
  ///
  /// @param signatureAlgorithmName the name of the signature algorithm
  /// @param digestAlgorithmName the name of the digest algorithm, if any
  /// @return an OID string, or null if none was found.
  static String? getSignatureMechanismOid(
      String signatureAlgorithmName, String? digestAlgorithmName) {
    switch (signatureAlgorithmName) {
      case 'RSA':
        return digestAlgorithmName != null
            ? rsaOidsByDigest[digestAlgorithmName] ?? CraftOID.rsa
            : CraftOID.rsa;
      case 'DSA':
        return digestAlgorithmName != null
            ? dsaOidsByDigest[digestAlgorithmName]
            : null;
      case 'ECDSA':
        return digestAlgorithmName != null
            ? ecdsaOidsByDigest[digestAlgorithmName]
            : null;
      case 'Ed25519':
        return CraftOID.ed25519;
      case 'Ed448':
        return CraftOID.ed448;
      case 'RSASSA-PSS':
      case 'RSA/PSS':
        return CraftOID.rsassaPss;
      default:
        return null;
    }
  }

  /// Gets the algorithm name for a certain id.
  ///
  /// @param oid an id (for instance "1.2.840.113549.1.1.1")
  /// @return an algorithm name (for instance "RSA")
  static String getAlgorithm(String oid) {
    return algorithmNames[oid] ?? oid;
  }

  /// Resolves the signing algorithm from its identifier and digest.
  ///
  /// @param oid an id of an algorithm
  /// @param digest digest of an algorithm
  /// @return name of the mechanism
  static String getMechanism(String oid, String digest) {
    final algorithm = getAlgorithm(oid);
    if (algorithm != oid) {
      return '${digest}with$algorithm';
    }
    return algorithm;
  }
}
