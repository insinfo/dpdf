/// Class containing all the OID values used by iText.
class OID {
  OID._();

  static const String pkcs7Data = "1.2.840.113549.1.7.1";
  static const String idData = "1.2.840.113549.1.7.1";
  static const String pkcs7SignedData = "1.2.840.113549.1.7.2";
  static const String rsa = "1.2.840.113549.1.1.1";
  static const String rsassaPss = "1.2.840.113549.1.1.10";
  static const String rsaWithSha256 = "1.2.840.113549.1.1.11";
  static const String aaSigningCertificateV1 = "1.2.840.113549.1.9.16.2.12";
  static const String aaSigningCertificateV2 = "1.2.840.113549.1.9.16.2.47";
  static const String aaEtsCommitmenttype = "1.2.840.113549.1.9.16.2.16";
  static const String mgf1 = "1.2.840.113549.1.1.8";
  static const String aaTimeStampToken = "1.2.840.113549.1.9.16.2.14";
  static const String authenticatedData = "1.2.840.113549.1.9.16.1.2";
  static const String contentType = "1.2.840.113549.1.9.3";
  static const String messageDigest = "1.2.840.113549.1.9.4";
  static const String signingTime = "1.2.840.113549.1.9.5";
  static const String cmsAlgorithmProtection = "1.2.840.113549.1.9.52";
  static const String dsa = "1.2.840.10040.4.1";
  static const String ecdsa = "1.2.840.10045.2.1";
  static const String adbeRevocation = "1.2.840.113583.1.1.8";
  static const String tsa = "1.2.840.113583.1.1.9.1";
  static const String md5 = "1.2.840.113549.2.5";
  static const String rsaWithSha3_512 = "2.16.840.1.101.3.4.3.16";
  static const String sha224 = "2.16.840.1.101.3.4.2.4";
  static const String sha256 = "2.16.840.1.101.3.4.2.1";
  static const String sha384 = "2.16.840.1.101.3.4.2.2";
  static const String sha512 = "2.16.840.1.101.3.4.2.3";
  static const String sha512_256 = "2.16.840.1.101.3.4.2.6";
  static const String sha3_224 = "2.16.840.1.101.3.4.2.7";
  static const String sha3_256 = "2.16.840.1.101.3.4.2.8";
  static const String sha3_384 = "2.16.840.1.101.3.4.2.9";
  static const String sha3_512 = "2.16.840.1.101.3.4.2.10";
  static const String shake256 = "2.16.840.1.101.3.4.2.12";
  static const String ed25519 = "1.3.101.112";
  static const String ed448 = "1.3.101.113";
  static const String ocsp = "1.3.6.1.5.5.7.48.1";
  static const String caIssuers = "1.3.6.1.5.5.7.48.2";
  static const String riOcspResponse = "1.3.6.1.5.5.7.16.2";
  static const String kdfPdfMacWrapKdf = "1.0.32004.1.1";
  static const String ctPdfMacIntegrityInfo = "1.0.32004.1.0";
  static const String mlDsa44 = "2.16.840.1.101.3.4.3.17";
  static const String mlDsa65 = "2.16.840.1.101.3.4.3.18";
  static const String mlDsa87 = "2.16.840.1.101.3.4.3.19";
  static const String slhDsaSha2_128s = "2.16.840.1.101.3.4.3.20";
  static const String slhDsaSha2_128f = "2.16.840.1.101.3.4.3.21";
  static const String slhDsaSha2_192s = "2.16.840.1.101.3.4.3.22";
  static const String slhDsaSha2_192f = "2.16.840.1.101.3.4.3.23";
  static const String slhDsaSha2_256s = "2.16.840.1.101.3.4.3.24";
  static const String slhDsaSha2_256f = "2.16.840.1.101.3.4.3.25";
  static const String slhDsaShake128s = "2.16.840.1.101.3.4.3.26";
  static const String slhDsaShake128f = "2.16.840.1.101.3.4.3.27";
  static const String slhDsaShake192s = "2.16.840.1.101.3.4.3.28";
  static const String slhDsaShake192f = "2.16.840.1.101.3.4.3.29";
  static const String slhDsaShake256s = "2.16.840.1.101.3.4.3.30";
  static const String slhDsaShake256f = "2.16.840.1.101.3.4.3.31";
}

/// Contains all OIDs used by iText in the context of X509 Extensions.
class X509Extensions {
  X509Extensions._();

  static const String authorityKeyIdentifier = "2.5.29.35";
  static const String subjectKeyIdentifier = "2.5.29.14";
  static const String keyUsage = "2.5.29.15";
  static const String certificatePolicies = "2.5.29.32";
  static const String policyMappings = "2.5.29.33";
  static const String subjectAlternativeName = "2.5.29.17";
  static const String issuerAlternativeName = "2.5.29.18";
  static const String subjectDirectoryAttributes = "2.5.29.9";
  static const String basicConstraints = "2.5.29.19";
  static const String nameConstraints = "2.5.29.30";
  static const String policyConstraints = "2.5.29.36";
  static const String extendedKeyUsage = "2.5.29.37";
  static const String crlDistributionPoints = "2.5.29.31";
  static const String inhibitAnyPolicy = "2.5.29.54";
  static const String freshestCrl = "2.5.29.46";
  static const String authorityInfoAccess = "1.3.6.1.5.5.7.1.1";
  static const String subjectInfoAccess = "1.3.6.1.5.5.7.1.11";
  static const String idKpTimestamping = "1.3.6.1.5.5.7.3.8";
  static const String idPkixOcspNoCheck = "1.3.6.1.5.5.7.48.1.5";
  static const String validityAssuredShortTerm = "0.4.0.194121.2.1";
  static const String noRevAvailable = "2.5.29.56";

  static const Set<String> supportedCriticalExtensions = {
    keyUsage,
    certificatePolicies,
    policyMappings,
    subjectAlternativeName,
    issuerAlternativeName,
    basicConstraints,
    nameConstraints,
    policyConstraints,
    extendedKeyUsage,
    crlDistributionPoints,
    inhibitAnyPolicy,
    idPkixOcspNoCheck,
  };
}
