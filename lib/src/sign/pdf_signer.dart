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
import '../forms/pdf_sig_field_lock.dart';
import '../forms/fields/pdf_form_creator.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_object.dart';
import 'access_permissions.dart';
import 'pdf_signature_reference.dart';
import 'signature_modification_analyzer.dart';

import '../forms/fields/pdf_signature_form_field.dart';
import 'simple_signature_appearance.dart';

/// Incremental mode preserves previous revisions; fullRewrite creates a new
/// document revision chain and does not preserve earlier signature integrity.
enum PdfSigningMode { incremental, fullRewrite }

/// Coordinates signature configuration and its visual representation.
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
      {WriterProperties? properties,
      PdfRepairedSaveMode repairedSaveMode = PdfRepairedSaveMode.reject,
      PdfSigningMode mode = PdfSigningMode.incremental}) {
    _originalOS = outputStream;
    properties ??= WriterProperties();
    _initDocument(reader, properties, repairedSaveMode, mode);
  }

  factory PdfSigner.fromBytes(Uint8List bytes, IOSink outputStream,
      {WriterProperties? properties,
      ReaderProperties? readerProperties,
      PdfRepairedSaveMode repairedSaveMode = PdfRepairedSaveMode.reject,
      PdfSigningMode mode = PdfSigningMode.incremental}) {
    return PdfSigner(PdfReader.fromBytes(bytes, readerProperties), outputStream,
        properties: properties, repairedSaveMode: repairedSaveMode, mode: mode);
  }

  /// Collects a signed revision in memory on VM, JavaScript and WebAssembly.
  factory PdfSigner.fromBytesBuilder(Uint8List bytes, BytesBuilder output,
      {WriterProperties? properties,
      ReaderProperties? readerProperties,
      PdfRepairedSaveMode repairedSaveMode = PdfRepairedSaveMode.reject,
      PdfSigningMode mode = PdfSigningMode.incremental}) {
    return PdfSigner.fromBytes(bytes, _BytesBuilderSink(output),
        properties: properties,
        readerProperties: readerProperties,
        repairedSaveMode: repairedSaveMode,
        mode: mode);
  }

  void _initDocument(PdfReader reader, WriterProperties properties,
      PdfRepairedSaveMode repairedSaveMode, PdfSigningMode mode) {
    _tempBuilder = BytesBuilder();

    _tempSink = _BytesBuilderSink(_tempBuilder!);

    // Use append mode for signing - essential for multiple signatures
    // Each signature creates a new PDF revision incrementally
    final stampingProperties = StampingProperties()
      ..repairedSaveMode = repairedSaveMode;
    if (mode == PdfSigningMode.incremental) stampingProperties.useAppendMode();

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
    final util = SignatureUtil(_document!);
    while (await util.doesSignatureFieldExist(name + step.toString())) {
      step++;
    }
    return name + step.toString();
  }

  /// Signs the document using the specified signature container.
  Future<void> signExternalContainer(
    ExternalSignatureContainer container,
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
    // Table 252: /M is the claimed time of signing.
    dic.setDate(PdfString(
        PdfDate(_signerProperties.getClaimedSignDate()).getValue()));

    container.modifySigningDictionary(dic.pdfRepresentation());

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
  /// @param subFilter the /SubFilter of table 252; one of adbe.pkcs7.detached,
  ///        adbe.pkcs7.sha1 or ETSI.CAdES.detached
  Future<void> signDetached(
    ExternalSignature externalSignature,
    List<Uint8List> chain, {
    List<CrlClient>? crlList,
    OcspClient? ocspClient,
    TSAClient? tsaClient,
    int estimatedSize = 8192,
    ExternalDigest? externalDigest,
    PdfName? subFilter,
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
    final selectedSubFilter = subFilter ?? PdfName.adbePkcs7Detached;
    if (selectedSubFilter != PdfName.adbePkcs7Detached &&
        selectedSubFilter != PdfName.adbePkcs7Sha1 &&
        selectedSubFilter != PdfName.etsiCadesDetached) {
      throw PdfException(
          'Unsupported signature /SubFilter ${selectedSubFilter.getValue()}');
    }
    // 12.8.3.3: adbe.pkcs7.sha1 encapsulates the SHA1 digest of the byte range
    // in the SignedData, the detached subfilters encapsulate nothing.
    final hasEncapContent = selectedSubFilter == PdfName.adbePkcs7Sha1;

    // Create Signature Dictionary
    final dic = PdfSignature.withFilter(
        PdfName.intern('Adobe.PPKLite'), selectedSubFilter);

    // Fixed: Removed unnecessary null checks
    dic.setReason(_signerProperties.getReason());
    dic.setLocation(_signerProperties.getLocation());
    dic.setSignatureCreator(_signerProperties.getSignatureCreator());
    dic.setContact(_signerProperties.getContact());

    // Table 252: /M is the claimed time of signing.
    dic.setDate(PdfString(
        PdfDate(_signerProperties.getClaimedSignDate()).getValue()));

    _cryptoDictionary = dic;

    final exc = <PdfName, int>{};
    exc[PdfName.contents] = estimatedSize * 2 + 2;

    await _preClose(exc);

    // Update ByteRange BEFORE hashing
    await _updateByteRange();

    // Create PKCS7
    final sgn = PdfPKCS7.forSigning(
        null, chain, hashAlgorithm, externalDigest ?? _DefaultDigest(),
        hasEncapContent: hasEncapContent, filterSubtype: selectedSubFilter);
    sgn.setSignDate(_signerProperties.getClaimedSignDate());

    // Get data to sign (the document with hole)
    final data = await _getRangeStream();

    // Calculate digest
    Uint8List? encapsulatedContent;
    final Uint8List hash;
    if (hasEncapContent) {
      // The SHA1 digest of the byte range is the encapsulated content and the
      // digest of that content is the one the signed attributes carry.
      encapsulatedContent = DigestAlgorithms.digestBytes(data, 'SHA1');
      final messageDigest = DigestAlgorithms.getMessageDigest(hashAlgorithm);
      messageDigest.update(encapsulatedContent);
      hash = messageDigest.digest();
    } else {
      final messageDigest = DigestAlgorithms.getMessageDigest(hashAlgorithm);
      // data is Uint8List
      messageDigest.update(data);
      hash = messageDigest.digest();
    }

    // Authenticated attributes
    final sh = sgn.buildAuthenticatedAttributes(hash);

    // Sign
    final extSignature = await externalSignature.sign(sh);

    sgn.setExternalSignatureValue(extSignature, encapsulatedContent,
        externalSignature.getSignatureAlgorithmName());

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
        .pdfRepresentation()
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
    while (s.length < 100) {
      s += " ";
    }

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

    _cryptoDictionary!.pdfRepresentation().attachToDocument(_document!);

    // Table 252: /Changes records what happened since the previous signature.
    await _recordChanges();

    PdfSigFieldLock? fieldLock = _signerProperties.getFieldLockDict();

    if (fieldExist) {
      // Populate existing field (Simplified)
      final field = await _acroForm!.getField(name);
      if (field != null) {
        // 12.8.2.4: when the field already carries a lock dictionary its
        // /Action and /Fields drive the FieldMDP transform of this signature.
        fieldLock ??= await _readExistingFieldLock(field.pdfRepresentation());
        if (_signerProperties.getFieldLockDict() != null) {
          _attachFieldLock(field.pdfRepresentation(), fieldLock);
        }
        field.put(PdfName.v, _cryptoDictionary!.pdfRepresentation());
        field.markChanged();
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
      final pageNum = _signerProperties.pageOrdinal();
      final page = await _document!.pageAt(pageNum);
      if (page == null) {
        throw StateError("Page $pageNum not found");
      }
      sigField.put(PdfName.p, page.pdfRepresentation().indirectHandle()!);

      // Add value
      sigField.put(PdfName.v, _cryptoDictionary!.pdfRepresentation());

      // Flag
      sigField.put(PdfName.f, PdfNumber(4)); // Print

      // Table 233: the signature field lock dictionary.
      _attachFieldLock(sigField, fieldLock);

      // Create Wrapper
      final fieldWrapper = PdfSignatureFormField(sigField);
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
      page.pdfRepresentation().put(PdfName.tabs, PdfName.s);
      page.pdfRepresentation().markChanged();
    }

    // 12.8.2: transform methods that guide the modification analysis.
    await _applyTransformMethods(fieldLock);

    // Set Up Exclusions (Placeholders)
    final byteRangePlaceholder = Uint8List(100);
    for (int i = 0; i < 100; i++) {
      byteRangePlaceholder[i] = 0x20; // spaces
    }

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

  /// Reads the `/Lock` entry of an existing signature field, ISO 32000-1
  /// table 233, and adopts it as the field lock of this signing operation.
  Future<PdfSigFieldLock?> _readExistingFieldLock(PdfDictionary field) async {
    final lock = await field.dictionaryEntry(PdfName.lock);
    return lock == null ? null : PdfSigFieldLock.fromDictionary(lock);
  }

  /// Writes the `/Lock` entry of a signature field.
  void _attachFieldLock(PdfDictionary field, PdfSigFieldLock? fieldLock) {
    if (fieldLock == null) return;
    final lockDictionary = fieldLock.pdfRepresentation();
    lockDictionary.attachToDocument(_document!);
    final handle = lockDictionary.indirectHandle();
    field.put(PdfName.lock, handle ?? lockDictionary);
  }

  /// Adds the `/Reference` array of table 252 for the transform methods this
  /// signature declares, and the `/Perms` entry a certification signature
  /// needs (12.8.4).
  Future<void> _applyTransformMethods(PdfSigFieldLock? fieldLock) async {
    final catalog = _document!.rootCatalog();
    final PdfObject? data = catalog.pdfRepresentation().indirectHandle();
    final references = PdfArray();

    final level = _signerProperties.getCertificationLevel();
    if (level != AccessPermissions.unspecified) {
      references.add(
          PdfSignatureReference.docMdp(level, data: data).pdfRepresentation());
    }

    if (fieldLock != null) {
      final action = await fieldLock.getFieldLockAction();
      if (action != null) {
        references.add(PdfSignatureReference.fieldMdp(action,
                fields: await fieldLock.getFieldLockFields(), data: data)
            .pdfRepresentation());
      }
    }

    if (references.size() == 0) return;
    _cryptoDictionary!.put(PdfName.reference, references);

    if (level == AccessPermissions.unspecified) return;
    final signatureHandle =
        _cryptoDictionary!.pdfRepresentation().indirectHandle();
    if (signatureHandle == null) return;
    final existing =
        await catalog.pdfRepresentation().dictionaryEntry(PdfName.perms);
    final permissions = existing ?? PdfDictionary();
    permissions.put(PdfName.docMDP, signatureHandle);
    permissions.markChanged();
    if (existing == null) {
      catalog.put(PdfName.perms, permissions);
    }
    catalog.pdfRepresentation().markChanged();
  }

  /// Fills the optional `/Changes` array of table 252 with the number of pages
  /// altered, fields altered and fields filled in since the previous signature.
  ///
  /// The computation compares the revision covered by the latest existing
  /// signature with the document as it was loaded; it is skipped silently when
  /// the document carries no signature yet or cannot be compared.
  Future<void> _recordChanges() async {
    try {
      final source = _document!.inputReader()?.getOriginalBytes();
      if (source == null) return;
      final util = SignatureUtil(_document!);
      final names = await util.getSignatureNames();
      if (names.isEmpty) return;
      Uint8List? latest;
      for (final signature in names) {
        final revision = await util.extractRevisionDocument(signature);
        if (revision == null) continue;
        if (latest == null || revision.length > latest.length) {
          latest = revision;
        }
      }
      if (latest == null || latest.length > source.length) return;
      // When the previous signature already covers the whole loaded file,
      // nothing was added between it and this one, and the three counts of
      // table 252 are all zero. That is a real answer, not a reason to leave
      // the entry out: a verifier reading /Changes is entitled to be told
      // that the document did not move.
      final List<int> counts;
      if (latest.length == source.length) {
        counts = const <int>[0, 0, 0];
      } else {
        counts =
            (await SignatureModificationAnalyzer.compare(latest, source))
                .toChangesArray();
      }
      final changes = PdfArray();
      for (final value in counts) {
        changes.add(PdfNumber.fromInt(value));
      }
      _cryptoDictionary!.put(SignatureReferenceNames.changes, changes);
    } catch (_) {
      // /Changes is optional; an unreadable earlier revision is not fatal.
    }
  }

  Future<void> _close(PdfDictionary dic) async {
    final contentsHex = await _cryptoDictionary!
        .pdfRepresentation()
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
        .pdfRepresentation()
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

class _DefaultDigest implements ExternalDigest {
  @override
  SigningDigest getMessageDigest(String hashAlgorithm) {
    return DigestAlgorithms.getMessageDigest(hashAlgorithm);
  }
}
