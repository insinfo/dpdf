import 'dart:typed_data';

/// Interface representing an X.509 certificate.
///
/// This interface abstracts the certificate operations to allow different
/// implementations (e.g., using pointycastle or native platform support).
abstract class IX509Certificate {
  /// Gets the issuer distinguished name.
  ///
  /// @return the issuer DN as a string
  String getIssuerDN();

  /// Gets the subject distinguished name.
  ///
  /// @return the subject DN as a string
  String getSubjectDN();

  /// Gets the serial number of the certificate.
  ///
  /// @return the serial number as a BigInt
  BigInt getSerialNumber();

  /// Gets the public key from the certificate.
  ///
  /// @return the DER-encoded public key bytes
  Uint8List getPublicKey();

  /// Gets the signature algorithm OID.
  ///
  /// @return the signature algorithm OID as a string
  String getSigAlgOID();

  /// Gets the signature algorithm name.
  ///
  /// @return the signature algorithm name
  String getSigAlgName();

  /// Gets the signature algorithm parameters.
  ///
  /// @return the DER-encoded parameters, or null if none
  Uint8List? getSigAlgParams();

  /// Gets the DER-encoded certificate.
  ///
  /// @return the DER-encoded certificate bytes
  Uint8List getEncoded();

  /// Gets the TBS (To-Be-Signed) certificate bytes.
  ///
  /// @return the TBS certificate bytes
  Uint8List getTbsCertificate();

  /// Gets an extension value by OID.
  ///
  /// @param oid the extension OID
  /// @return the extension value, or null if not present
  Uint8List? getExtensionValue(String oid);

  /// Verifies the certificate signature using the issuer's public key.
  ///
  /// @param issuerPublicKey the issuer's public key (DER-encoded)
  /// @throws Exception if verification fails
  void verify(Uint8List issuerPublicKey);

  /// Gets the critical extension OIDs.
  ///
  /// @return a set of OID strings
  Set<String> getCriticalExtensionOids();

  /// Checks if the certificate is valid at the given time.
  ///
  /// @param time the time to check
  /// @throws Exception if the certificate is not valid
  void checkValidity(DateTime time);

  /// Gets the not-before date.
  ///
  /// @return the not-before date
  DateTime getNotBefore();

  /// Gets the not-after date.
  ///
  /// @return the not-after date
  DateTime getNotAfter();

  /// Gets the extended key usage extension.
  ///
  /// @return list of OID strings, or null if not present
  List<String>? getExtendedKeyUsage();

  /// Gets the key usage extension.
  ///
  /// @return boolean array for key usage, or null if not present
  List<bool>? getKeyUsage();

  /// Gets the basic constraints extension.
  ///
  /// @return the path length constraint, or -1 if not a CA
  int getBasicConstraints();

  /// Indicates whether this is a CA certificate.
  ///
  /// @return true if this is a CA certificate
  bool isCA() => getBasicConstraints() >= 0;
}

/// Factory for creating X.509 certificates.
abstract class IX509CertificateParser {
  /// Parses a certificate from DER-encoded bytes.
  ///
  /// @param encoded the DER-encoded certificate
  /// @return the parsed certificate
  IX509Certificate parseCertificate(Uint8List encoded);

  /// Parses multiple certificates from a byte array.
  ///
  /// @param encoded the encoded certificates (may be DER or PEM)
  /// @return list of parsed certificates
  List<IX509Certificate> parseCertificates(Uint8List encoded);
}
