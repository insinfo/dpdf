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
class CraftPdfSignature extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  /// Creates new PdfSignature.
  CraftPdfSignature() : super(CraftPdfDictionary()) {
    put(CraftPdfName.type, CraftPdfName.sig);
  }

  /// Creates new PdfSignature.
  ///
  /// @param filter signature validation handler name
  /// @param subFilter signature encoding identifier
  CraftPdfSignature.withFilter(CraftPdfName filter, CraftPdfName subFilter)
      : super(CraftPdfDictionary()) {
    put(CraftPdfName.type, CraftPdfName.sig);
    put(CraftPdfName.filter, filter);
    put(CraftPdfName.subFilter, subFilter);
  }

  /// Creates new PdfSignature instance from the provided PdfDictionary.
  CraftPdfSignature.fromDictionary(CraftPdfDictionary sigDictionary)
      : super(sigDictionary) {
    // Contents should be marked as unencrypted if needed
    // This is handled during signature processing
  }

  /// A name that describes the encoding of the signature value and key
  /// information in the signature dictionary.
  ///
  /// @return a PdfName which usually has a value either
  /// PdfName.Adbe_pkcs7_detached or PdfName.ETSI_CAdES_DETACHED.
  Future<CraftPdfName?> getSubFilter() async {
    return await pdfRepresentation().nameEntry(CraftPdfName.subFilter);
  }

  /// The type of PDF object that the wrapped dictionary describes.
  ///
  /// If present, shall be PdfName.Sig for a signature dictionary or
  /// PdfName.DocTimeStamp for a timestamp signature dictionary.
  /// The default value is: PdfName.Sig.
  ///
  /// @return a PdfName that identifies type of the wrapped dictionary,
  /// returns null if it is not explicitly specified.
  Future<CraftPdfName?> getSignatureType() async {
    return await pdfRepresentation().nameEntry(CraftPdfName.type);
  }

  /// Sets the /ByteRange.
  ///
  /// @param range an array of pairs of integers that specifies the byte range
  /// used in the digest calculation. A pair consists of the starting byte
  /// offset and the length.
  void setByteRange(List<int> range) {
    final array = CraftPdfArray();
    for (final i in range) {
      array.add(CraftPdfNumber.fromInt(i));
    }
    put(CraftPdfName.byteRange, array);
  }

  /// Gets the /ByteRange.
  ///
  /// @return an array of pairs of integers that specifies the byte range used
  /// in the digest calculation.
  Future<CraftPdfArray?> getByteRange() async {
    return await pdfRepresentation().arrayEntry(CraftPdfName.byteRange);
  }

  /// Sets the /Contents value to the specified bytes.
  ///
  /// @param contents a bytes representing the digest
  void setContents(Uint8List contents) {
    final contentsString =
        CraftPdfString.fromBytes(contents).setHexWriting(true);
    // contentsString.markAsUnencryptedObject();
    put(CraftPdfName.contents, contentsString);
  }

  /// Gets the /Contents entry value.
  ///
  /// See ISO 32000-1 12.8.1, Table 252 – Entries in a signature dictionary.
  ///
  /// @return the signature content
  Future<CraftPdfString?> getContents() async {
    return await pdfRepresentation().stringEntry(CraftPdfName.contents);
  }

  /// Sets the /Cert value of this signature.
  ///
  /// @param cert the bytes representing the certificate chain
  void setCert(Uint8List cert) {
    put(CraftPdfName.cert, CraftPdfString.fromBytes(cert));
  }

  /// Gets the /Cert entry value of this signature.
  ///
  /// See ISO 32000-1 12.8.1, Table 252 – Entries in a signature dictionary.
  ///
  /// @return the signature cert
  Future<CraftPdfString?> getCert() async {
    return await pdfRepresentation().stringEntry(CraftPdfName.cert);
  }

  /// Gets the /Cert entry value of this signature.
  ///
  /// /Cert entry required when SubFilter is adbe.x509.rsa_sha1.
  /// May be array or byte string.
  ///
  /// @return the signature cert value
  Future<CraftPdfObject?> getCertObject() async {
    final certAsStr = await pdfRepresentation().stringEntry(CraftPdfName.cert);
    final certAsArray = await pdfRepresentation().arrayEntry(CraftPdfName.cert);
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
    put(CraftPdfName.name, CraftPdfString(name));
  }

  /// Gets the /Name of the person signing the document.
  ///
  /// @return name of the person signing the document.
  Future<String?> getName() async {
    final nameStr = await pdfRepresentation().stringEntry(CraftPdfName.name);
    final nameName = await pdfRepresentation().nameEntry(CraftPdfName.name);
    if (nameStr != null) {
      return nameStr.decodeMappingText();
    } else {
      return nameName?.getValue();
    }
  }

  /// Sets the /M value (time of signing).
  ///
  /// Should only be used if the time of signing is not available in the signature.
  ///
  /// @param date time of signing as PdfString
  void setDate(CraftPdfString date) {
    put(CraftPdfName.m, date);
  }

  /// Gets the /M value.
  ///
  /// Should only be used if the time of signing is not available in the signature.
  ///
  /// @return PdfString which denotes time of signing.
  Future<CraftPdfString?> getDate() async {
    return await pdfRepresentation().stringEntry(CraftPdfName.m);
  }

  /// Sets the /Location value.
  ///
  /// @param location physical location of signing
  void setLocation(String location) {
    put(CraftPdfName.location, CraftPdfString(location));
  }

  /// Gets the /Location entry value.
  ///
  /// @return physical location of signing.
  Future<String?> getLocation() async {
    final locationStr =
        await pdfRepresentation().stringEntry(CraftPdfName.location);
    return locationStr?.decodeMappingText();
  }

  /// Sets the /Reason value.
  ///
  /// @param reason reason for signing
  void setReason(String reason) {
    put(CraftPdfName.reason, CraftPdfString(reason));
  }

  /// Gets the /Reason value.
  ///
  /// @return reason for signing
  Future<String?> getReason() async {
    final reasonStr =
        await pdfRepresentation().stringEntry(CraftPdfName.reason);
    return reasonStr?.decodeMappingText();
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
  /// @param contactInfo signer contact details
  void setContact(String contactInfo) {
    put(CraftPdfName.contactInfo, CraftPdfString(contactInfo));
  }

  /// Add new key-value pair to the signature dictionary.
  ///
  /// @param key PdfName to be added as a key
  /// @param value PdfObject to be added as a value
  /// @return the same PdfSignature instance
  CraftPdfSignature put(CraftPdfName key, CraftPdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
    return this;
  }

  @override
  bool requiresIndirectStorage() {
    return true;
  }

  /// Gets the PdfSignatureBuildProperties instance if it exists, if
  /// not it adds a new one and returns this.
  ///
  /// @return PdfSignatureBuildProperties
  CraftPdfSignatureBuildProperties getPdfSignatureBuildProperties() {
    // Access the map directly for synchronous operation
    final map = pdfRepresentation().getMap();
    final obj = map?[CraftPdfName.propBuild];
    if (obj == null || obj is! CraftPdfDictionary) {
      final newDict = CraftPdfDictionary();
      put(CraftPdfName.propBuild, newDict);
      return CraftPdfSignatureBuildProperties.fromDictionary(newDict);
    }
    return CraftPdfSignatureBuildProperties.fromDictionary(obj);
  }
}
