import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:dpdf/src/kernel/pdf/stamping_properties.dart';

import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/pdf_writer.dart';
import '../kernel/pdf/writer_properties.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_dictionary.dart';

import '../kernel/pdf/pdf_literal.dart';
import '../kernel/pdf/pdf_date.dart';
import '../kernel/exceptions/pdf_exception.dart';
import 'pdf_signature.dart';
import 'signer_properties.dart';
import 'i_external_signature.dart';
import 'i_external_signature_container.dart';
import 'i_external_digest.dart';
import 'i_crl_client.dart';
import 'i_ocsp_client.dart';
import 'i_tsa_client.dart';
import 'signature_util.dart';
import 'pdf_pkcs7.dart';
import 'digest_algorithms.dart';
import '../forms/pdf_acro_form.dart';
import '../forms/fields/pdf_form_creator.dart';

import '../forms/fields/pdf_signature_form_field.dart';
import 'simple_signature_appearance.dart';

/// Takes care of the cryptographic options and appearances that form a signature.
class PdfSigner {
  PdfDocument? _document;
  SignerProperties _signerProperties = SignerProperties();
  PdfSignature? _cryptoDictionary;
  PdfAcroForm? _acroForm;

  bool _closed = false;
  bool _preClosed = false;

  late IOSink _originalOS;

  // Temporary storage for the signed document before filling the signature
  BytesBuilder? _tempBuilder;
  IOSink? _tempSink;
  final Map<PdfName, PdfLiteral> _exclusionLocations = {};

  /// Creates a PdfSigner instance.
  ///
  /// @param reader the PdfReader to open the document
  /// @param outputStream the sink to write the signed document to
  /// @param properties properties for the signing document
  PdfSigner(PdfReader reader, IOSink outputStream,
      {WriterProperties? properties}) {
    _originalOS = outputStream;
    properties ??= WriterProperties();
    _initDocument(reader, properties);
  }

  factory PdfSigner.fromBytes(Uint8List bytes, IOSink outputStream,
      {WriterProperties? properties}) {
    return PdfSigner(PdfReader.fromBytes(bytes), outputStream,
        properties: properties);
  }

  void _initDocument(PdfReader reader, WriterProperties properties) {
    _tempBuilder = BytesBuilder();

    // Copy original bytes
    // Essential for append mode and correct offset calculations
    final originalBytes = reader.getOriginalBytes();
    if (originalBytes != null) {
      _tempBuilder!.add(originalBytes);
    }

    _tempSink = _BytesBuilderSink(_tempBuilder!);

    // Use append mode for signing - essential for multiple signatures
    // Each signature creates a new PDF revision incrementally
    final stampingProperties = StampingProperties()..useAppendMode();

    _document = PdfDocument(
        reader: reader,
        writer: PdfWriter(_tempSink!,
            properties: properties, initialPosition: _tempBuilder!.length),
        properties: stampingProperties);
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

  PdfSigner setFieldName(String name) {
    _signerProperties.setFieldName(name);
    return this;
  }

  PdfSigner setPageNumber(int page) {
    _signerProperties.setPageNumber(page);
    return this;
  }

  PdfSigner setReason(String reason) {
    _signerProperties.setReason(reason);
    return this;
  }

  PdfSigner setLocation(String loc) {
    _signerProperties.setLocation(loc);
    return this;
  }

  PdfSigner setContact(String contact) {
    _signerProperties.setContact(contact);
    return this;
  }

  PdfSigner setSignatureCreator(String creator) {
    _signerProperties.setSignatureCreator(creator);
    return this;
  }

  String? getFieldName() => _signerProperties.getFieldName();
  int getPageNumber() => _signerProperties.getPageNumber();
  String? getReason() => _signerProperties.getReason();
  String? getLocation() => _signerProperties.getLocation();
  String? getContact() => _signerProperties.getContact();
  String getSignatureCreator() => _signerProperties.getSignatureCreator();

  /// Gets a new signature field name that doesn't clash with any existing name.
  ///
  /// @return A new signature field name.
  Future<String> getNewSigFieldName() async {
    var name = 'Signature';
    var step = 1;
    final util = SignatureUtil(_document!);
    while (await util.doesSignatureFieldExist(name + step.toString())) {
      step++;
    }
    return name + step.toString();
  }

  /// Signs the document using the specified signature container.
  Future<void> signExternalContainer(
    IExternalSignatureContainer container,
    int estimatedSize,
  ) async {
    _checkClosed();
    await _document!.load();

    if (_signerProperties.getFieldName() == null) {
      _signerProperties.setFieldName(await getNewSigFieldName());
    }

    _acroForm = await PdfFormCreator.getAcroForm(_document!, true);

    // Create Signature Dictionary
    final dic = PdfSignature();
    dic.setReason(_signerProperties.getReason());
    dic.setLocation(_signerProperties.getLocation());
    dic.setSignatureCreator(_signerProperties.getSignatureCreator());
    dic.setContact(_signerProperties.getContact());
    dic.setDate(PdfString(PdfDate(DateTime.now()).getValue()));

    container.modifySigningDictionary(dic.getPdfObject());

    _cryptoDictionary = dic;

    final exc = <PdfName, int>{};
    exc[PdfName.contents] = estimatedSize * 2 + 2;

    await _preClose(exc);

    // Update ByteRange BEFORE hashing
    await _updateByteRange();

    final data = await _getRangeStream();
    final encodedSig = await container.sign(Stream.value(data));

    if (estimatedSize < encodedSig.length) {
      throw PdfException("Not enough space for signature");
    }

    final paddedSig = Uint8List(estimatedSize);
    paddedSig.setRange(0, encodedSig.length, encodedSig);

    final dic2 = PdfDictionary();
    dic2.put(
        PdfName.contents, PdfString.fromBytes(paddedSig).setHexWriting(true));

    await _close(dic2);
    _closed = true;
  }

  /// Signs the document using a private key (Detached mode).
  ///
  /// @param externalSignature the external signature implementation
  /// @param chain the certificate chain (as list of DER-encoded certificates)
  /// @param estimatedSize the estimated size of the signature
  Future<void> signDetached(
    IExternalSignature externalSignature,
    List<Uint8List> chain, {
    List<ICrlClient>? crlList,
    IOcspClient? ocspClient,
    ITSAClient? tsaClient,
    int estimatedSize = 8192,
    IExternalDigest? externalDigest,
  }) async {
    _checkClosed();
    await _document!.load();

    // Check fields
    if (_signerProperties.getFieldName() == null) {
      _signerProperties.setFieldName(await getNewSigFieldName());
    }

    // Prepare AcroForm
    _acroForm = await PdfFormCreator.getAcroForm(_document!, true);

    if (estimatedSize == 0) {
      estimatedSize = 8192;
    }

    final hashAlgorithm = externalSignature.getDigestAlgorithmName();

    // Create Signature Dictionary
    final dic = PdfSignature.withFilter(
        PdfName.intern('Adobe.PPKLite'), PdfName.adbePkcs7Detached);

    // Fixed: Removed unnecessary null checks
    dic.setReason(_signerProperties.getReason());
    dic.setLocation(_signerProperties.getLocation());
    dic.setSignatureCreator(_signerProperties.getSignatureCreator());
    dic.setContact(_signerProperties.getContact());

    dic.setDate(PdfString(PdfDate(DateTime.now()).getValue()));

    _cryptoDictionary = dic;

    final exc = <PdfName, int>{};
    exc[PdfName.contents] = estimatedSize * 2 + 2;

    await _preClose(exc);

    // Update ByteRange BEFORE hashing
    await _updateByteRange();

    // Create PKCS7
    final sgn = PdfPKCS7.forSigning(
        null, chain, hashAlgorithm, externalDigest ?? _DefaultDigest(),
        hasEncapContent: false);

    // Get data to sign (the document with hole)
    final data = await _getRangeStream();

    // Calculate digest
    final messageDigest = DigestAlgorithms.getMessageDigest(hashAlgorithm);
    // data is Uint8List
    messageDigest.update(data);
    final hash = messageDigest.digest();

    // Authenticated attributes
    final sh = sgn.buildAuthenticatedAttributes(hash);

    // Sign
    final extSignature = await externalSignature.sign(sh);

    sgn.setExternalSignatureValue(
        extSignature, null, externalSignature.getSignatureAlgorithmName());

    // Get Final PKCS7
    // Get Final PKCS7
    final encodedSig = await sgn.getEncodedPKCS7(hash, tsaClient: tsaClient);

    if (estimatedSize < encodedSig.length) {
      throw PdfException("Not enough space for signature");
    }

    final paddedSig = Uint8List(estimatedSize);
    paddedSig.setRange(0, encodedSig.length, encodedSig);

    final dic2 = PdfDictionary();
    dic2.put(
        PdfName.contents, PdfString.fromBytes(paddedSig).setHexWriting(true));

    await _close(dic2);
    _closed = true;
  }

  /// Updates the ByteRange placeholder in the document with actual values.
  /// This must be called BEFORE hashing to ensure the signature integrity.
  Future<void> _updateByteRange() async {
    final totalLen = _tempBuilder!.length;
    final byteRangePos = _exclusionLocations[PdfName.byteRange]!.getOffset();
    final contentsHex = await _cryptoDictionary!
        .getPdfObject()
        .get(PdfName.contents) as PdfString;
    final contentsPos = contentsHex.getOffset();
    final contentsLen = contentsHex.getValueBytes()!.length * 2 + 2;

    final range = <int>[
      0,
      contentsPos,
      contentsPos + contentsLen,
      totalLen - (contentsPos + contentsLen)
    ];

    // Format ByteRange string: "[ 0 123 456 789 ]"
    var s = "[ ${range[0]} ${range[1]} ${range[2]} ${range[3]} ]";
    if (s.length > 100) {
      throw PdfException("ByteRange string too long for placeholder");
    }
    while (s.length < 100) s += " ";

    final brBytes = s.codeUnits;
    final bytes = _tempBuilder!.toBytes();

    // Update the tempBuilder bytes in place
    for (int i = 0; i < brBytes.length; i++) {
      bytes[byteRangePos + i] = brBytes[i];
    }
    
    // We need to update _tempBuilder with the modified bytes
    _tempBuilder!.clear();
    _tempBuilder!.add(bytes);
  }

  Future<void> _preClose(Map<PdfName, int> exclusionSizes) async {
    if (_preClosed) {
      throw StateError("Document already pre-closed");
    }
    _preClosed = true;

    // Ensure field exists or create it
    final name = _signerProperties.getFieldName()!;
    final util = SignatureUtil(_document!);
    final fieldExist = await util.doesSignatureFieldExist(name);

    await _acroForm!.setSignatureFlags(
        PdfAcroForm.SIGNATURE_EXIST | PdfAcroForm.APPEND_ONLY);

    if (_cryptoDictionary == null) {
      throw StateError("No crypto dictionary defined");
    }

    _cryptoDictionary!.getPdfObject().makeIndirect(_document!);

    if (fieldExist) {
      // Populate existing field (Simplified)
      final field = await _acroForm!.getField(name);
      if (field != null) {
        field.put(PdfName.v, _cryptoDictionary!.getPdfObject());
        field.setModified();
      }
    } else {
      // Create new field
      final sigField = PdfDictionary();
      sigField.put(PdfName.ft, PdfName.sig);
      sigField.put(PdfName.subtype, PdfName.widget);
      sigField.put(PdfName.t, PdfString(name));
      // PDF/UA: TU key (Alternative description) is mandatory for form fields
      sigField.put(PdfName.tu, PdfString('Assinatura Digital: $name'));

      // Rectangle
      final rect = _signerProperties.getPageRect();
      sigField.put(PdfName.rect, rect.toPdfArray());

      // Page
      final pageNum = _signerProperties.getPageNumber();
      final page = await _document!.getPage(pageNum);
      if (page == null) {
        throw StateError("Page $pageNum not found");
      }
      sigField.put(PdfName.p, page.getPdfObject().getIndirectReference()!);

      // Add value
      sigField.put(PdfName.v, _cryptoDictionary!.getPdfObject());

      // Flag
      sigField.put(PdfName.f, PdfNumber(4)); // Print

      // Create Wrapper
      final fieldWrapper = PdfSignatureFormField(sigField);
      fieldWrapper.getPdfObject().makeIndirect(_document!);
      
      // Generate Appearance
      if (rect.getWidth() > 0 && rect.getHeight() > 0) {
          final app = SimpleSignatureAppearance(_signerProperties);
          final n2 = await app.generate(_document!);
          fieldWrapper.setSignatureAppearanceLayer(n2);
      }
      
      // Add to form
      await _acroForm!.addField(fieldWrapper, page);

      // PDF/UA: Every page with annotations shall have /Tabs /S
      page.getPdfObject().put(PdfName.tabs, PdfName.s);
      page.getPdfObject().setModified();
    }

    // Set Up Exclusions (Placeholders)
    final byteRangePlaceholder = Uint8List(100);
    for (int i = 0; i < 100; i++) byteRangePlaceholder[i] = 0x20; // spaces

    final byteRangeLit = PdfLiteral.fromBytes(byteRangePlaceholder);
    _exclusionLocations[PdfName.byteRange] = byteRangeLit;
    _cryptoDictionary!.put(PdfName.byteRange, byteRangeLit);

    exclusionSizes.forEach((key, size) {
      // Only Contents supported directly for now
      final hexString =
          PdfString.fromBytes(Uint8List((size - 2) ~/ 2)).setHexWriting(true);
      _cryptoDictionary!.put(key, hexString);
    });

    // Write the document
    await _document!.close();
  }

  Future<void> _close(PdfDictionary dic) async {
    final contentsHex = await _cryptoDictionary!
        .getPdfObject()
        .get(PdfName.contents) as PdfString;
    final contentsPos = contentsHex.getOffset();

    // Write Contents
    final newContents =
        (await dic.get(PdfName.contents) as PdfString).getValueBytes()!;

    // We overwrite content at contentsPos with Hex String representation
    var hex = "";
    for (final b in newContents) {
      hex += b.toRadixString(16).padLeft(2, '0').toUpperCase();
    }

    final bytes = _tempBuilder!.toBytes();
    
    bytes[contentsPos] = 0x3C; // <
    var idx = contentsPos + 1;
    final hexUnits = hex.codeUnits;
    for (int i = 0; i < hexUnits.length; i++) {
      bytes[idx++] = hexUnits[i];
    }
    bytes[idx] = 0x3E; // >

    // Write to original OS
    _originalOS.add(bytes);
    await _originalOS.close();
  }

  Future<Uint8List> _getRangeStream() async {
    final bytes = _tempBuilder!.toBytes();

    final contentsHex = await _cryptoDictionary!
        .getPdfObject()
        .get(PdfName.contents) as PdfString;
    final contentsPos = contentsHex.getOffset();
    final contentsEnd =
        contentsPos + contentsHex.getValueBytes()!.length * 2 + 2;

    final chunk1 = bytes.sublist(0, contentsPos);
    final chunk2 = bytes.sublist(contentsEnd);

    final b = BytesBuilder();
    b.add(chunk1);
    b.add(chunk2);
    return b.toBytes();
  }

  void _checkClosed() {
    if (_closed) {
      throw StateError('This instance of PdfSigner has been already closed.');
    }
  }

  Future<void> close() async {
    _closed = true;
  }
}

class _BytesBuilderSink implements IOSink {
  final BytesBuilder builder;
  _BytesBuilderSink(this.builder);

  @override
  Encoding get encoding => throw UnimplementedError();

  @override
  set encoding(Encoding encoding) => throw UnimplementedError();

  @override
  void add(List<int> data) {
    builder.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    throw error;
  }

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      builder.add(data);
    }
  }

  @override
  Future close() async {}

  @override
  Future get done => Future.value();

  @override
  Future flush() async {}

  @override
  void write(Object? object) {
    if (object != null) {
      add(object.toString().codeUnits);
    }
  }

  @override
  void writeAll(Iterable objects, [String separator = ""]) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    builder.addByte(charCode);
  }

  @override
  void writeln([Object? object = ""]) {
    write(object);
    writeCharCode(10);
  }
}

class _DefaultDigest implements IExternalDigest {
  @override
  IMessageDigest getMessageDigest(String hashAlgorithm) {
    return DigestAlgorithms.getMessageDigest(hashAlgorithm);
  }
}
