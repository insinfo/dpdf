import '../platform/io.dart';
import 'dart:typed_data';
import 'dart:convert';

import 'package:dpdf/src/kernel/pdf/stamping_properties.dart';

import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/reader_properties.dart';
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
import 'external_signature.dart';
import 'external_signature_container.dart';
import 'external_digest.dart';
import 'crl_client.dart';
import 'ocsp_client.dart';
import 'tsa_client.dart';
import 'signature_util.dart';
import 'pdf_pkcs7.dart';
import 'digest_algorithms.dart';
import '../forms/pdf_acro_form.dart';
import '../forms/fields/pdf_form_creator.dart';

import '../forms/fields/pdf_signature_form_field.dart';
import 'simple_signature_appearance.dart';

/// Incremental mode preserves previous revisions; fullRewrite creates a new
/// document revision chain and does not preserve earlier signature integrity.
enum PdfSigningMode { incremental, fullRewrite }

/// Coordinates signature configuration and its visual representation.
class CraftPdfSigner {
  CraftPdfDocument? _document;
  CraftSignerProperties _signerProperties = CraftSignerProperties();
  CraftPdfSignature? _cryptoDictionary;
  CraftPdfAcroForm? _acroForm;

  bool _closed = false;
  bool _preClosed = false;

  late IOSink _originalOS;

  // Temporary storage for the signed document before filling the signature
  BytesBuilder? _tempBuilder;
  IOSink? _tempSink;
  final Map<CraftPdfName, CraftPdfLiteral> _exclusionLocations = {};

  /// Creates a PdfSigner instance.
  ///
  /// @param reader the PdfReader to open the document
  /// @param outputStream the sink to write the signed document to
  /// @param properties properties for the signing document
  CraftPdfSigner(CraftPdfReader reader, IOSink outputStream,
      {CraftWriterProperties? properties,
      PdfRepairedSaveMode repairedSaveMode = PdfRepairedSaveMode.reject,
      PdfSigningMode mode = PdfSigningMode.incremental}) {
    _originalOS = outputStream;
    properties ??= CraftWriterProperties();
    _initDocument(reader, properties, repairedSaveMode, mode);
  }

  factory CraftPdfSigner.fromBytes(Uint8List bytes, IOSink outputStream,
      {CraftWriterProperties? properties,
      CraftReaderProperties? readerProperties,
      PdfRepairedSaveMode repairedSaveMode = PdfRepairedSaveMode.reject,
      PdfSigningMode mode = PdfSigningMode.incremental}) {
    return CraftPdfSigner(
        CraftPdfReader.fromBytes(bytes, readerProperties), outputStream,
        properties: properties, repairedSaveMode: repairedSaveMode, mode: mode);
  }

  /// Collects a signed revision in memory on VM, JavaScript and WebAssembly.
  factory CraftPdfSigner.fromBytesBuilder(Uint8List bytes, BytesBuilder output,
      {CraftWriterProperties? properties,
      CraftReaderProperties? readerProperties,
      PdfRepairedSaveMode repairedSaveMode = PdfRepairedSaveMode.reject,
      PdfSigningMode mode = PdfSigningMode.incremental}) {
    return CraftPdfSigner.fromBytes(bytes, _BytesBuilderSink(output),
        properties: properties,
        readerProperties: readerProperties,
        repairedSaveMode: repairedSaveMode,
        mode: mode);
  }

  void _initDocument(CraftPdfReader reader, CraftWriterProperties properties,
      PdfRepairedSaveMode repairedSaveMode, PdfSigningMode mode) {
    _tempBuilder = BytesBuilder();

    _tempSink = _BytesBuilderSink(_tempBuilder!);

    // Use append mode for signing - essential for multiple signatures
    // Each signature creates a new PDF revision incrementally
    final stampingProperties = CraftStampingProperties()
      ..repairedSaveMode = repairedSaveMode;
    if (mode == PdfSigningMode.incremental) stampingProperties.useAppendMode();

    _document = CraftPdfDocument(
        reader: reader,
        writer: CraftPdfWriter(_tempSink!,
            properties: properties, initialPosition: _tempBuilder!.length),
        properties: stampingProperties);
  }

  /// Sets the properties to be used in signing operations.
  ///
  /// @param properties the signer properties
  /// @return this instance to support fluent interface
  CraftPdfSigner setSignerProperties(CraftSignerProperties properties) {
    _signerProperties = properties;
    return this;
  }

  /// Gets the properties to be used in signing operations.
  ///
  /// @return the signer properties
  CraftSignerProperties getSignerProperties() => _signerProperties;

  /// Returns the user made signature dictionary.
  ///
  /// This is the dictionary at the /V key of the signature field.
  ///
  /// @return the user made signature dictionary
  CraftPdfSignature? getSignatureDictionary() => _cryptoDictionary;

  /// Gets the PdfDocument associated with this instance.
  ///
  /// @return the PdfDocument associated with this instance
  CraftPdfDocument? getDocument() => _document;

  CraftPdfSigner setFieldName(String name) {
    _signerProperties.setFieldName(name);
    return this;
  }

  CraftPdfSigner setPageNumber(int page) {
    _signerProperties.setPageNumber(page);
    return this;
  }

  CraftPdfSigner setReason(String reason) {
    _signerProperties.setReason(reason);
    return this;
  }

  CraftPdfSigner setLocation(String loc) {
    _signerProperties.setLocation(loc);
    return this;
  }

  CraftPdfSigner setContact(String contact) {
    _signerProperties.setContact(contact);
    return this;
  }

  CraftPdfSigner setSignatureCreator(String creator) {
    _signerProperties.setSignatureCreator(creator);
    return this;
  }

  String? getFieldName() => _signerProperties.getFieldName();
  int pageOrdinal() => _signerProperties.pageOrdinal();
  String? getReason() => _signerProperties.getReason();
  String? getLocation() => _signerProperties.getLocation();
  String? getContact() => _signerProperties.getContact();
  String getSignatureCreator() => _signerProperties.getSignatureCreator();

  /// Chooses an unused name for a new signature field.
  ///
  /// @return A new signature field name.
  Future<String> getNewSigFieldName() async {
    var name = 'Signature';
    var step = 1;
    final util = CraftSignatureUtil(_document!);
    while (await util.doesSignatureFieldExist(name + step.toString())) {
      step++;
    }
    return name + step.toString();
  }

  /// Signs the document using the specified signature container.
  Future<void> signExternalContainer(
    CraftExternalSignatureContainer container,
    int estimatedSize,
  ) async {
    _checkClosed();
    await _document!.load();

    if (_signerProperties.getFieldName() == null) {
      _signerProperties.setFieldName(await getNewSigFieldName());
    }

    _acroForm = await CraftPdfFormCreator.getAcroForm(_document!, true);

    // Create Signature Dictionary
    final dic = CraftPdfSignature();
    dic.setReason(_signerProperties.getReason());
    dic.setLocation(_signerProperties.getLocation());
    dic.setSignatureCreator(_signerProperties.getSignatureCreator());
    dic.setContact(_signerProperties.getContact());
    dic.setDate(CraftPdfString(CraftPdfDate(DateTime.now()).getValue()));

    container.modifySigningDictionary(dic.pdfRepresentation());

    _cryptoDictionary = dic;

    final exc = <CraftPdfName, int>{};
    exc[CraftPdfName.contents] = estimatedSize * 2 + 2;

    await _preClose(exc);

    // Update ByteRange BEFORE hashing
    await _updateByteRange();

    final data = await _getRangeStream();
    final encodedSig = await container.sign(Stream.value(data));

    if (estimatedSize < encodedSig.length) {
      throw CraftPdfException("Not enough space for signature");
    }

    final paddedSig = Uint8List(estimatedSize);
    paddedSig.setRange(0, encodedSig.length, encodedSig);

    final dic2 = CraftPdfDictionary();
    dic2.put(CraftPdfName.contents,
        CraftPdfString.fromBytes(paddedSig).setHexWriting(true));

    await _close(dic2);
    _closed = true;
  }

  /// Signs the document using a private key (Detached mode).
  ///
  /// @param externalSignature the external signature implementation
  /// @param chain the certificate chain (as list of DER-encoded certificates)
  /// @param estimatedSize the estimated size of the signature
  Future<void> signDetached(
    CraftExternalSignature externalSignature,
    List<Uint8List> chain, {
    List<CraftCrlClient>? crlList,
    CraftOcspClient? ocspClient,
    CraftTSAClient? tsaClient,
    int estimatedSize = 8192,
    CraftExternalDigest? externalDigest,
  }) async {
    _checkClosed();
    await _document!.load();

    // Check fields
    if (_signerProperties.getFieldName() == null) {
      _signerProperties.setFieldName(await getNewSigFieldName());
    }

    // Prepare AcroForm
    _acroForm = await CraftPdfFormCreator.getAcroForm(_document!, true);

    if (estimatedSize == 0) {
      estimatedSize = 8192;
    }

    final hashAlgorithm = externalSignature.getDigestAlgorithmName();

    // Create Signature Dictionary
    final dic = CraftPdfSignature.withFilter(
        CraftPdfName.intern('Adobe.PPKLite'), CraftPdfName.adbePkcs7Detached);

    // Fixed: Removed unnecessary null checks
    dic.setReason(_signerProperties.getReason());
    dic.setLocation(_signerProperties.getLocation());
    dic.setSignatureCreator(_signerProperties.getSignatureCreator());
    dic.setContact(_signerProperties.getContact());

    dic.setDate(CraftPdfString(CraftPdfDate(DateTime.now()).getValue()));

    _cryptoDictionary = dic;

    final exc = <CraftPdfName, int>{};
    exc[CraftPdfName.contents] = estimatedSize * 2 + 2;

    await _preClose(exc);

    // Update ByteRange BEFORE hashing
    await _updateByteRange();

    // Create PKCS7
    final sgn = CraftPdfPKCS7.forSigning(
        null, chain, hashAlgorithm, externalDigest ?? _DefaultDigest(),
        hasEncapContent: false);

    // Get data to sign (the document with hole)
    final data = await _getRangeStream();

    // Calculate digest
    final messageDigest = CraftDigestAlgorithms.getMessageDigest(hashAlgorithm);
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
      throw CraftPdfException("Not enough space for signature");
    }

    final paddedSig = Uint8List(estimatedSize);
    paddedSig.setRange(0, encodedSig.length, encodedSig);

    final dic2 = CraftPdfDictionary();
    dic2.put(CraftPdfName.contents,
        CraftPdfString.fromBytes(paddedSig).setHexWriting(true));

    await _close(dic2);
    _closed = true;
  }

  /// Updates the ByteRange placeholder in the document with actual values.
  /// This must be called BEFORE hashing to ensure the signature integrity.
  Future<void> _updateByteRange() async {
    final totalLen = _tempBuilder!.length;
    final byteRangePos =
        _exclusionLocations[CraftPdfName.byteRange]!.getOffset();
    final contentsHex = await _cryptoDictionary!
        .pdfRepresentation()
        .get(CraftPdfName.contents) as CraftPdfString;
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
      throw CraftPdfException("ByteRange string too long for placeholder");
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

  Future<void> _preClose(Map<CraftPdfName, int> exclusionSizes) async {
    if (_preClosed) {
      throw StateError("Document already pre-closed");
    }
    _preClosed = true;

    // Ensure field exists or create it
    final name = _signerProperties.getFieldName()!;
    final util = CraftSignatureUtil(_document!);
    final fieldExist = await util.doesSignatureFieldExist(name);

    await _acroForm!.setSignatureFlags(
        CraftPdfAcroForm.SIGNATURE_EXIST | CraftPdfAcroForm.APPEND_ONLY);

    if (_cryptoDictionary == null) {
      throw StateError("No crypto dictionary defined");
    }

    _cryptoDictionary!.pdfRepresentation().attachToDocument(_document!);

    if (fieldExist) {
      // Populate existing field (Simplified)
      final field = await _acroForm!.getField(name);
      if (field != null) {
        field.put(CraftPdfName.v, _cryptoDictionary!.pdfRepresentation());
        field.markChanged();
      }
    } else {
      // Create new field
      final sigField = CraftPdfDictionary();
      sigField.put(CraftPdfName.ft, CraftPdfName.sig);
      sigField.put(CraftPdfName.subtype, CraftPdfName.widget);
      sigField.put(CraftPdfName.t, CraftPdfString(name));
      // PDF/UA: TU key (Alternative description) is mandatory for form fields
      sigField.put(
          CraftPdfName.tu, CraftPdfString('Assinatura Digital: $name'));

      // Rectangle
      final rect = _signerProperties.getPageRect();
      sigField.put(CraftPdfName.rect, rect.toPdfArray());

      // Page
      final pageNum = _signerProperties.pageOrdinal();
      final page = await _document!.pageAt(pageNum);
      if (page == null) {
        throw StateError("Page $pageNum not found");
      }
      sigField.put(CraftPdfName.p, page.pdfRepresentation().indirectHandle()!);

      // Add value
      sigField.put(CraftPdfName.v, _cryptoDictionary!.pdfRepresentation());

      // Flag
      sigField.put(CraftPdfName.f, CraftPdfNumber(4)); // Print

      // Create Wrapper
      final fieldWrapper = CraftPdfSignatureFormField(sigField);
      fieldWrapper.pdfRepresentation().attachToDocument(_document!);

      // Generate Appearance
      if (rect.getWidth() > 0 && rect.getHeight() > 0) {
        final app = SimpleSignatureAppearance(_signerProperties);
        final n2 = await app.generate(_document!);
        fieldWrapper.setSignatureAppearanceLayer(n2);
      }

      // Add to form
      await _acroForm!.addField(fieldWrapper, page);

      // PDF/UA: Every page with annotations shall have /Tabs /S
      page.pdfRepresentation().put(CraftPdfName.tabs, CraftPdfName.s);
      page.pdfRepresentation().markChanged();
    }

    // Set Up Exclusions (Placeholders)
    final byteRangePlaceholder = Uint8List(100);
    for (int i = 0; i < 100; i++) byteRangePlaceholder[i] = 0x20; // spaces

    final byteRangeLit = CraftPdfLiteral.fromBytes(byteRangePlaceholder);
    _exclusionLocations[CraftPdfName.byteRange] = byteRangeLit;
    _cryptoDictionary!.put(CraftPdfName.byteRange, byteRangeLit);

    exclusionSizes.forEach((key, size) {
      // Only Contents supported directly for now
      final hexString = CraftPdfString.fromBytes(Uint8List((size - 2) ~/ 2))
          .setHexWriting(true);
      _cryptoDictionary!.put(key, hexString);
    });

    // Write the document
    await _document!.close();
  }

  Future<void> _close(CraftPdfDictionary dic) async {
    final contentsHex = await _cryptoDictionary!
        .pdfRepresentation()
        .get(CraftPdfName.contents) as CraftPdfString;
    final contentsPos = contentsHex.getOffset();

    // Write Contents
    final newContents = (await dic.get(CraftPdfName.contents) as CraftPdfString)
        .getValueBytes()!;

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
        .pdfRepresentation()
        .get(CraftPdfName.contents) as CraftPdfString;
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

class _DefaultDigest implements CraftExternalDigest {
  @override
  SigningDigest getMessageDigest(String hashAlgorithm) {
    return CraftDigestAlgorithms.getMessageDigest(hashAlgorithm);
  }
}
