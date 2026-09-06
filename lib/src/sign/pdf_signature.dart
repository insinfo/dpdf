import 'dart:typed_data';

import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/pdf_object_wrapper.dart';
import 'pdf_signature_build_properties.dart';

/// Represents the signature dictionary.
class PdfSignature extends PdfObjectWrapper<PdfDictionary> {
  /// Creates new PdfSignature.
  PdfSignature() : super(PdfDictionary()) {
    put(PdfName.type, PdfName.sig);
  }

  /// Creates new PdfSignature.
  ///
  /// @param filter PdfName of the signature handler to use when validating this signature
  /// @param subFilter PdfName that describes the encoding of the signature
  PdfSignature.withFilter(PdfName filter, PdfName subFilter)
      : super(PdfDictionary()) {
    put(PdfName.type, PdfName.sig);
    put(PdfName.filter, filter);
    put(PdfName.subFilter, subFilter);
  }

  /// Creates new PdfSignature instance from the provided PdfDictionary.
  PdfSignature.fromDictionary(PdfDictionary sigDictionary)
      : super(sigDictionary) {
    // Contents should be marked as unencrypted if needed
    // This is handled during signature processing
  }

  /// A name that describes the encoding of the signature value and key
  /// information in the signature dictionary.
  ///
  /// @return a PdfName which usually has a value either
  /// PdfName.Adbe_pkcs7_detached or PdfName.ETSI_CAdES_DETACHED.
  Future<PdfName?> getSubFilter() async {
    return await getPdfObject().getAsName(PdfName.subFilter);
  }

  /// The type of PDF object that the wrapped dictionary describes.
  ///
  /// If present, shall be PdfName.Sig for a signature dictionary or
  /// PdfName.DocTimeStamp for a timestamp signature dictionary.
  /// The default value is: PdfName.Sig.
  ///
  /// @return a PdfName that identifies type of the wrapped dictionary,
  /// returns null if it is not explicitly specified.
  Future<PdfName?> getSignatureType() async {
    return await getPdfObject().getAsName(PdfName.type);
  }

  /// Sets the /ByteRange.
  ///
  /// @param range an array of pairs of integers that specifies the byte range
  /// used in the digest calculation. A pair consists of the starting byte
  /// offset and the length.
  void setByteRange(List<int> range) {
    final array = PdfArray();
    for (final i in range) {
      array.add(PdfNumber.fromInt(i));
    }
    put(PdfName.byteRange, array);
  }

  /// Gets the /ByteRange.
  ///
  /// @return an array of pairs of integers that specifies the byte range used
  /// in the digest calculation.
  Future<PdfArray?> getByteRange() async {
    return await getPdfObject().getAsArray(PdfName.byteRange);
  }

  /// Sets the /Contents value to the specified bytes.
  ///
  /// @param contents a bytes representing the digest
  void setContents(Uint8List contents) {
    final contentsString = PdfString.fromBytes(contents).setHexWriting(true);
    // contentsString.markAsUnencryptedObject();
    put(PdfName.contents, contentsString);
  }

  /// Gets the /Contents entry value.
  ///
  /// See ISO 32000-1 12.8.1, Table 252 – Entries in a signature dictionary.
  ///
  /// @return the signature content
  Future<PdfString?> getContents() async {
    return await getPdfObject().getAsString(PdfName.contents);
  }

  /// Sets the /Cert value of this signature.
  ///
  /// @param cert the bytes representing the certificate chain
  void setCert(Uint8List cert) {
    put(PdfName.cert, PdfString.fromBytes(cert));
  }

  /// Gets the /Cert entry value of this signature.
  ///
  /// See ISO 32000-1 12.8.1, Table 252 – Entries in a signature dictionary.
  ///
  /// @return the signature cert
  Future<PdfString?> getCert() async {
    return await getPdfObject().getAsString(PdfName.cert);
  }

  /// Gets the /Cert entry value of this signature.
  ///
  /// /Cert entry required when SubFilter is adbe.x509.rsa_sha1.
  /// May be array or byte string.
  ///
  /// @return the signature cert value
  Future<PdfObject?> getCertObject() async {
    final certAsStr = await getPdfObject().getAsString(PdfName.cert);
    final certAsArray = await getPdfObject().getAsArray(PdfName.cert);
    if (certAsStr != null) {
      return certAsStr;
    } else {
      return certAsArray;
    }
  }

  /// Sets the /Name of the person signing the document.
  ///
  /// @param name name of the person signing the document
  void setName(String name) {
    put(PdfName.name, PdfString(name));
  }

  /// Gets the /Name of the person signing the document.
  ///
  /// @return name of the person signing the document.
  Future<String?> getName() async {
    final nameStr = await getPdfObject().getAsString(PdfName.name);
    final nameName = await getPdfObject().getAsName(PdfName.name);
    if (nameStr != null) {
      return nameStr.toUnicodeString();
    } else {
      return nameName?.getValue();
    }
  }

  /// Sets the /M value (time of signing).
  ///
  /// Should only be used if the time of signing is not available in the signature.
  ///
  /// @param date time of signing as PdfString
  void setDate(PdfString date) {
    put(PdfName.m, date);
  }

  /// Gets the /M value.
  ///
  /// Should only be used if the time of signing is not available in the signature.
  ///
  /// @return PdfString which denotes time of signing.
  Future<PdfString?> getDate() async {
    return await getPdfObject().getAsString(PdfName.m);
  }

  /// Sets the /Location value.
  ///
  /// @param location physical location of signing
  void setLocation(String location) {
    put(PdfName.location, PdfString(location));
  }

  /// Gets the /Location entry value.
  ///
  /// @return physical location of signing.
  Future<String?> getLocation() async {
    final locationStr = await getPdfObject().getAsString(PdfName.location);
    return locationStr?.toUnicodeString();
  }

  /// Sets the /Reason value.
  ///
  /// @param reason reason for signing
  void setReason(String reason) {
    put(PdfName.reason, PdfString(reason));
  }

  /// Gets the /Reason value.
  ///
  /// @return reason for signing
  Future<String?> getReason() async {
    final reasonStr = await getPdfObject().getAsString(PdfName.reason);
    return reasonStr?.toUnicodeString();
  }

  /// Sets the signature creator name in the PdfSignatureBuildProperties dictionary.
  ///
  /// @param signatureCreator name of the signature creator
  void setSignatureCreator(String? signatureCreator) {
    if (signatureCreator != null) {
      getPdfSignatureBuildProperties().setSignatureCreator(signatureCreator);
    }
  }

  /// Sets the /ContactInfo value.
  ///
  /// @param contactInfo information to contact the person who signed this document
  void setContact(String contactInfo) {
    put(PdfName.contactInfo, PdfString(contactInfo));
  }

  /// Add new key-value pair to the signature dictionary.
  ///
  /// @param key PdfName to be added as a key
  /// @param value PdfObject to be added as a value
  /// @return the same PdfSignature instance
  PdfSignature put(PdfName key, PdfObject value) {
    getPdfObject().put(key, value);
    setModified();
    return this;
  }

  @override
  bool isWrappedObjectMustBeIndirect() {
    return true;
  }

  /// Gets the PdfSignatureBuildProperties instance if it exists, if
  /// not it adds a new one and returns this.
  ///
  /// @return PdfSignatureBuildProperties
  PdfSignatureBuildProperties getPdfSignatureBuildProperties() {
    // Access the map directly for synchronous operation
    final map = getPdfObject().getMap();
    final obj = map?[PdfName.propBuild];
    if (obj == null || obj is! PdfDictionary) {
      final newDict = PdfDictionary();
      put(PdfName.propBuild, newDict);
      return PdfSignatureBuildProperties.fromDictionary(newDict);
    }
    return PdfSignatureBuildProperties.fromDictionary(obj);
  }
}
