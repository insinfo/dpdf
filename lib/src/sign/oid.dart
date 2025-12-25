/// Standard OIDs used in digital signatures.
///
///
class OID {
  OID._();

  // RSA
  static const String rsa = '1.2.840.113549.1.1.1';
  static const String rsaMd2 = '1.2.840.113549.1.1.2';
  static const String rsaMd5 = '1.2.840.113549.1.1.4';
  static const String rsaSha1 = '1.2.840.113549.1.1.5';
  static const String rsaSha224 = '1.2.840.113549.1.1.14';
  static const String rsaSha256 = '1.2.840.113549.1.1.11';
  static const String rsaSha384 = '1.2.840.113549.1.1.12';
  static const String rsaSha512 = '1.2.840.113549.1.1.13';
  static const String rsassaPss = '1.2.840.113549.1.1.10';

  // DSA
  static const String dsa = '1.2.840.10040.4.1';
  static const String dsaSha1 = '1.2.840.10040.4.3';
  static const String dsaSha224 = '2.16.840.1.101.3.4.3.1';
  static const String dsaSha256 = '2.16.840.1.101.3.4.3.2';
  static const String dsaSha384 = '2.16.840.1.101.3.4.3.3';
  static const String dsaSha512 = '2.16.840.1.101.3.4.3.4';

  // ECDSA
  static const String ecPublicKey = '1.2.840.10045.2.1';
  static const String ecdsaSha1 = '1.2.840.10045.4.1';
  static const String ecdsa = '1.2.840.10045.4.3';
  static const String ecdsaSha256 = '1.2.840.10045.4.3.2';
  static const String ecdsaSha384 = '1.2.840.10045.4.3.3';
  static const String ecdsaSha512 = '1.2.840.10045.4.3.4';

  // EdDSA
  static const String ed25519 = '1.3.101.112';
  static const String ed448 = '1.3.101.113';

  // Hash algorithms
  static const String sha1 = '1.3.14.3.2.26';
  static const String sha224 = '2.16.840.1.101.3.4.2.4';
  static const String sha256 = '2.16.840.1.101.3.4.2.1';
  static const String sha384 = '2.16.840.1.101.3.4.2.2';
  static const String sha512 = '2.16.840.1.101.3.4.2.3';
  static const String sha3_224 = '2.16.840.1.101.3.4.2.7';
  static const String sha3_256 = '2.16.840.1.101.3.4.2.8';
  static const String sha3_384 = '2.16.840.1.101.3.4.2.9';
  static const String sha3_512 = '2.16.840.1.101.3.4.2.10';
  static const String md5 = '1.2.840.113549.2.5';
  static const String md2 = '1.2.840.113549.2.2';
  static const String ripemd160 = '1.3.36.3.2.1';

  // CMS Content types
  static const String data = '1.2.840.113549.1.7.1';
  static const String signedData = '1.2.840.113549.1.7.2';
  static const String envelopedData = '1.2.840.113549.1.7.3';
  static const String digestedData = '1.2.840.113549.1.7.5';
  static const String encryptedData = '1.2.840.113549.1.7.6';
  static const String tstInfo = '1.2.840.113549.1.9.16.1.4';

  // Attribute types
  static const String contentType = '1.2.840.113549.1.9.3';
  static const String messageDigest = '1.2.840.113549.1.9.4';
  static const String signingTime = '1.2.840.113549.1.9.5';
  static const String signingCertificate = '1.2.840.113549.1.9.16.2.12';
  static const String signingCertificateV2 = '1.2.840.113549.1.9.16.2.47';
  static const String signatureTimeStampToken = '1.2.840.113549.1.9.16.2.14';
  static const String adobeRevocation = '1.2.840.113583.1.1.8';
}
