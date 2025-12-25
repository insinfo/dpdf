import 'dart:typed_data';

import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/geom/rectangle.dart';
import 'pdf_signature.dart';
import 'signer_properties.dart';
import 'i_external_signature.dart';
import 'i_external_signature_container.dart';
import 'access_permissions.dart';

/// Takes care of the cryptographic options and appearances that form a signature.
///
/// TODO: This is a partial implementation - many methods need to be completed
class PdfSigner {
  PdfDocument? _document;
  SignerProperties _signerProperties = SignerProperties();
  PdfSignature? _cryptoDictionary;

  // ignore: unused_field - will be used when implementation is complete
  final List<int>? _originalDocument;
  // ignore: unused_field - will be used when implementation is complete
  final Sink<List<int>>? _outputSink;

  bool _closed = false;

  /// Creates a PdfSigner instance.
  ///
  /// @param reader the PdfReader to open the document
  /// @param outputSink the sink to write the signed document to
  /// @param append true if appending, false to create new
  PdfSigner._(this._originalDocument, this._outputSink) {
    // TODO: Initialize document properly
  }

  /// Creates a PdfSigner instance from a PdfReader.
  ///
  /// @param reader the PdfReader for the document to sign
  /// @param outputSink the sink to write the signed document to
  static Future<PdfSigner> create(
    PdfReader reader,
    Sink<List<int>> outputSink, {
    bool append = true,
  }) async {
    // TODO: Implement proper initialization with PdfReader
    final signer = PdfSigner._(null, outputSink);
    return signer;
  }

  /// Creates a PdfSigner from bytes.
  static Future<PdfSigner> fromBytes(
    Uint8List documentBytes,
    Sink<List<int>> outputSink, {
    bool append = true,
  }) async {
    final signer = PdfSigner._(documentBytes, outputSink);
    return signer;
  }

  /// Sets the properties to be used in signing operations.
  ///
  /// @param properties the signer properties
  /// @return this instance to support fluent interface
  PdfSigner setSignerProperties(SignerProperties properties) {
    _signerProperties = properties;
    return this;
  }

  /// Gets the properties to be used in signing operations.
  ///
  /// @return the signer properties
  SignerProperties getSignerProperties() => _signerProperties;

  /// Returns the user made signature dictionary.
  ///
  /// This is the dictionary at the /V key of the signature field.
  ///
  /// @return the user made signature dictionary
  PdfSignature? getSignatureDictionary() => _cryptoDictionary;

  /// Gets the PdfDocument associated with this instance.
  ///
  /// @return the PdfDocument associated with this instance
  PdfDocument? getDocument() => _document;

  /// Gets a new signature field name that doesn't clash with any existing name.
  ///
  /// @return A new signature field name.
  Future<String> getNewSigFieldName() async {
    // TODO: Check for existing fields
    return 'Signature1';
  }

  /// Signs the document using the specified signature container.
  ///
  /// @param container the external signature container
  /// @param estimatedSize the estimated size of the signature
  Future<void> signExternalContainer(
    IExternalSignatureContainer container,
    int estimatedSize,
  ) async {
    _checkClosed();
    // TODO: Implement signing with external container
    throw UnimplementedError('signExternalContainer not yet implemented');
  }

  /// Signs the document using a private key.
  ///
  /// @param externalSignature the external signature implementation
  /// @param chain the certificate chain (as list of DER-encoded certificates)
  /// @param estimatedSize the estimated size of the signature
  Future<void> signDetached(
    IExternalSignature externalSignature,
    List<Uint8List> chain, {
    int estimatedSize = 8192,
    AccessPermissions? certificationLevel,
  }) async {
    _checkClosed();
    // TODO: Implement detached signing
    throw UnimplementedError('signDetached not yet implemented');
  }

  /// Signs the document with a timestamp only (no signature).
  ///
  /// @param tsa the TSA client
  /// @param estimatedSize the estimated size of the timestamp
  Future<void> timestamp(
    /* ITSAClient tsa, */
    int estimatedSize,
  ) async {
    _checkClosed();
    // TODO: Implement timestamping
    throw UnimplementedError('timestamp not yet implemented');
  }

  /// Closes the signer and releases resources.
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      // TODO: Clean up resources
    }
  }

  void _checkClosed() {
    if (_closed) {
      throw StateError('This instance of PdfSigner has been already closed.');
    }
  }

  /// Gets the field name to be signed.
  String? getFieldName() => _signerProperties.getFieldName();

  /// Sets the field name to be signed.
  void setFieldName(String fieldName) {
    _signerProperties.setFieldName(fieldName);
  }

  /// Gets the page number for the signature.
  int getPageNumber() => _signerProperties.getPageNumber();

  /// Sets the page number for the signature.
  void setPageNumber(int pageNumber) {
    _signerProperties.setPageNumber(pageNumber);
  }

  /// Gets the rectangle for the signature field.
  Rectangle getPageRect() => _signerProperties.getPageRect();

  /// Sets the rectangle for the signature field.
  void setPageRect(Rectangle rect) {
    _signerProperties.setPageRect(rect);
  }

  /// Gets the signing reason.
  String getReason() => _signerProperties.getReason();

  /// Sets the signing reason.
  void setReason(String reason) {
    _signerProperties.setReason(reason);
  }

  /// Gets the signing location.
  String getLocation() => _signerProperties.getLocation();

  /// Sets the signing location.
  void setLocation(String location) {
    _signerProperties.setLocation(location);
  }

  /// Gets the certification level.
  AccessPermissions getCertificationLevel() =>
      _signerProperties.getCertificationLevel();

  /// Sets the certification level.
  void setCertificationLevel(AccessPermissions level) {
    _signerProperties.setCertificationLevel(level);
  }

  /// Gets the signature creator.
  String getSignatureCreator() => _signerProperties.getSignatureCreator();

  /// Sets the signature creator.
  void setSignatureCreator(String creator) {
    _signerProperties.setSignatureCreator(creator);
  }

  /// Gets the contact information.
  String getContact() => _signerProperties.getContact();

  /// Sets the contact information.
  void setContact(String contact) {
    _signerProperties.setContact(contact);
  }
}
