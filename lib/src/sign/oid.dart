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

  // X.509 Extensions
  static const String subjectKeyIdentifier = '2.5.29.14';
  static const String keyUsage = '2.5.29.15';
  static const String privateKeyUsagePeriod = '2.5.29.16';
  static const String subjectAlternativeName = '2.5.29.17';
  static const String issuerAlternativeName = '2.5.29.18';
  static const String basicConstraints = '2.5.29.19';
  static const String crlNumber = '2.5.29.20';
  static const String reasonCode = '2.5.29.21';
  static const String instructionCode = '2.5.29.23';
  static const String invalidityDate = '2.5.29.24';
  static const String deltaCrlIndicator = '2.5.29.27';
  static const String issuingDistributionPoint = '2.5.29.28';
  static const String certificateIssuer = '2.5.29.29';
  static const String nameConstraints = '2.5.29.30';
  static const String crlDistributionPoints = '2.5.29.31';
  static const String certificatePolicies = '2.5.29.32';
  static const String policyMappings = '2.5.29.33';
  static const String authorityKeyIdentifier = '2.5.29.35';
  static const String policyConstraints = '2.5.29.36';
  static const String extendedKeyUsage = '2.5.29.37';
  static const String freshestCrl = '2.5.29.46';
  static const String inhibitAnyPolicy = '2.5.29.54';
  static const String authorityInfoAccess = '1.3.6.1.5.5.7.1.1';
  static const String subjectInfoAccess = '1.3.6.1.5.5.7.1.11';
  static const String logoType = '1.3.6.1.5.5.7.1.12';
  static const String biometricInfo = '1.3.6.1.5.5.7.1.2';
  static const String qcStatements = '1.3.6.1.5.5.7.1.3';
  static const String auditIdentity = '1.3.6.1.5.5.7.1.4';
  static const String noRevAvail = '2.5.29.56';
  static const String targetInformation = '2.5.29.55';

  // AIA Access Methods
  static const String ocsp = '1.3.6.1.5.5.7.48.1';
  static const String caIssuers = '1.3.6.1.5.5.7.48.2';
  static const String timeStamping = '1.3.6.1.5.5.7.3.8';
  static const String ocspResponse = '1.3.6.1.5.5.7.48.1.1';
}
