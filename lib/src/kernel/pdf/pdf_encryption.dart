import 'dart:typed_data';

import 'package:dpdf/src/commons/utils/encoding_util.dart';
import 'package:dpdf/src/commons/utils/system_util.dart';
import 'package:dpdf/src/kernel/crypto/crypt_filter.dart';
import 'package:dpdf/src/kernel/crypto/crypt_filter_cipher.dart';
import 'package:dpdf/src/kernel/crypto/digest_algorithms.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_encryption.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/pub_key_security_handler.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/security_handler.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_handler_using_aes_128.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_handler_using_aes_256.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_handler_using_standard_128.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_handler_using_standard_40.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_security_handler.dart';
import 'package:dpdf/src/kernel/exceptions/kernel_exception_message_constant.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/encryption_constants.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_version.dart';
import 'package:dpdf/src/pki/rsa.dart';
import 'package:dpdf/src/sign/x509_certificate.dart';

/// The `/Encrypt` dictionary of ISO 32000-1:2008, 7.6 "Encryption", together
/// with the security handler that computes the file encryption key.
///
/// The class covers the standard security handler of 7.6.3 for revisions 2 to
/// 6, the public-key security handlers of 7.6.4 and the crypt filters of
/// 7.6.5. Two rules of 7.6 are enforced here rather than by the caller:
/// 7.6.1 leaves the contents of the encryption dictionary unencrypted, and
/// 7.5.7 forbids encrypting strings inside an object stream separately,
/// because the object stream itself is already encrypted.
class PdfEncryption extends PdfObjectWrapper<PdfDictionary> {
  /// Legacy `/V` style selectors kept for callers that used them.
  static const int standardEncryption40 = 2;
  static const int standardEncryption128 = 3;
  static const int aes128 = 4;
  static const int aes256 = 5;
  static const int aesGcm = 6;
  static const int defaultKeyLength = 40;

  static int _seq = SystemUtil.getTimeBasedSeed();

  int _cryptoMode = 0;
  int? _permissions;
  bool _encryptMetadata = true;
  bool _embeddedFilesOnly = false;
  Uint8List? _documentId;
  SecurityHandler? _securityHandler;
  CryptFilterConfiguration? _cryptFilters;
  int _objectNumber = 0;
  int _generation = 0;
  bool _inObjectStream = false;

  PdfEncryption() : super(PdfDictionary());

  PdfEncryption._(super.dictionary) {
    setForbidRelease();
  }

  /// Builds a standard security handler and its encryption dictionary.
  ///
  /// [encryptionAlgorithm] is one of the [EncryptionConstants] selectors,
  /// optionally combined with [EncryptionConstants.doNotEncryptMetadata] or
  /// [EncryptionConstants.embeddedFilesOnly].
  factory PdfEncryption.standard({
    Uint8List? userPassword,
    Uint8List? ownerPassword,
    int permissions = 0,
    int encryptionAlgorithm = EncryptionConstants.standardEncryption40,
    Uint8List? documentId,
    PdfVersion? version,
  }) {
    final dictionary = PdfDictionary();
    final encryption = PdfEncryption._(dictionary);
    encryption._cryptoMode = encryptionAlgorithm;
    encryption._documentId = documentId;
    encryption._encryptMetadata = (encryptionAlgorithm &
            EncryptionConstants.doNotEncryptMetadata) ==
        0;
    encryption._embeddedFilesOnly = (encryptionAlgorithm &
            EncryptionConstants.embeddedFilesOnly) ==
        EncryptionConstants.embeddedFilesOnly;
    final mode = encryptionAlgorithm & EncryptionConstants.encryptionMask;
    final encryptMetadata = encryption._encryptMetadata;
    final embeddedFilesOnly = encryption._embeddedFilesOnly;

    StandardSecurityHandler handler;
    switch (mode) {
      case EncryptionConstants.standardEncryption40:
        handler = StandardHandlerUsingStandard40(
            dictionary,
            userPassword,
            ownerPassword,
            permissions,
            encryptMetadata,
            embeddedFilesOnly,
            documentId);
        break;
      case EncryptionConstants.standardEncryption128:
        handler = StandardHandlerUsingStandard128(
            dictionary,
            userPassword,
            ownerPassword,
            permissions,
            encryptMetadata,
            embeddedFilesOnly,
            documentId);
        break;
      case EncryptionConstants.encryptionAes128:
        handler = StandardHandlerUsingAes128(
            dictionary,
            userPassword,
            ownerPassword,
            permissions,
            encryptMetadata,
            embeddedFilesOnly,
            documentId);
        break;
      case EncryptionConstants.encryptionAes256:
        handler = StandardHandlerUsingAes256(
            dictionary,
            userPassword,
            ownerPassword,
            permissions,
            encryptMetadata,
            embeddedFilesOnly,
            version);
        break;
      default:
        throw PdfException(
            KernelExceptionMessageConstant.noCompatibleEncryptionFound);
    }
    if (mode == EncryptionConstants.standardEncryption128 ||
        mode == EncryptionConstants.encryptionAes128) {
      // Table 20: /Length is the bit length of the file encryption key.
      dictionary.put(PdfName.length, PdfNumber.fromInt(128));
    }
    encryption._securityHandler = handler;
    encryption._permissions = handler.getPermissions();
    encryption._cryptFilters =
        _configurationFor(mode, encryptMetadata, embeddedFilesOnly);
    return encryption;
  }

  /// Builds a public-key security handler and its encryption dictionary
  /// (ISO 32000-1:2008, 7.6.4).
  factory PdfEncryption.publicKey({
    required List<PublicKeyRecipientGroup> recipients,
    int encryptionAlgorithm = EncryptionConstants.encryptionAes128,
    Uint8List? documentId,
  }) {
    final dictionary = PdfDictionary();
    final encryption = PdfEncryption._(dictionary);
    final encryptMetadata =
        (encryptionAlgorithm & EncryptionConstants.doNotEncryptMetadata) == 0;
    final embeddedFilesOnly =
        (encryptionAlgorithm & EncryptionConstants.embeddedFilesOnly) ==
            EncryptionConstants.embeddedFilesOnly;
    final handler = PubKeySecurityHandler.create(
      encryptionDictionary: dictionary,
      groups: recipients,
      encryptionAlgorithm: encryptionAlgorithm,
      encryptMetadata: encryptMetadata,
      embeddedFilesOnly: embeddedFilesOnly,
    );
    encryption._cryptoMode = encryptionAlgorithm;
    encryption._documentId = documentId;
    encryption._encryptMetadata = encryptMetadata;
    encryption._embeddedFilesOnly = embeddedFilesOnly;
    encryption._securityHandler = handler;
    encryption._permissions = handler.permissions;
    encryption._cryptFilters =
        CryptFilterConfiguration.uniform(handler.defaultFilter);
    if (embeddedFilesOnly) {
      encryption._cryptFilters = CryptFilterConfiguration(
        filters: {handler.defaultFilter.name.getValue(): handler.defaultFilter},
        streamFilter: CryptFilter.identity,
        stringFilter: CryptFilter.identity,
        embeddedFileFilter: handler.defaultFilter,
      );
    }
    return encryption;
  }

  /// Creates a PdfEncryption instance based on an existing standard encryption
  /// dictionary, without authenticating the password.
  PdfEncryption.fromDictionary(
      super.pdfDict, Uint8List password, Uint8List documentId) {
    setForbidRelease();
    _documentId = documentId;
  }

  /// Reads an encryption dictionary protected by the standard security handler
  /// and authenticates [password].
  static Future<PdfEncryption> createFromDictionary(
      PdfDictionary pdfDict, Uint8List password, Uint8List documentId) async {
    final encryption = PdfEncryption._(pdfDict);
    encryption._documentId = documentId;
    await encryption._readStandardHandler(pdfDict, password, documentId);
    return encryption;
  }

  /// Reads a public-key encryption dictionary and recovers the file encryption
  /// key with the private key belonging to [certificate].
  static Future<PdfEncryption> createFromDictionaryWithCertificate(
      PdfDictionary pdfDict,
      X509Certificate certificate,
      RSAPrivateKey privateKey,
      Uint8List documentId) async {
    final encryption = PdfEncryption._(pdfDict);
    encryption._documentId = documentId;
    final handler =
        await PubKeySecurityHandler.read(pdfDict, certificate, privateKey);
    encryption._securityHandler = handler;
    encryption._permissions = handler.permissions;
    encryption._encryptMetadata = handler.encryptMetadata;
    encryption._embeddedFilesOnly = handler.embeddedFilesOnly;
    encryption._cryptoMode = handler.encryptionAlgorithm;
    final version =
        (await pdfDict.numberEntry(PdfName.v))?.intValue() ?? 1;
    if (version >= 4) {
      encryption._cryptFilters =
          await CryptFilterConfiguration.fromEncryptionDictionary(pdfDict);
    } else {
      encryption._cryptFilters =
          CryptFilterConfiguration.uniform(handler.defaultFilter);
    }
    return encryption;
  }

  Future<void> _readStandardHandler(PdfDictionary pdfDict, Uint8List password,
      Uint8List? documentId) async {
    final filter = await pdfDict.nameEntry(PdfName.filter);
    if (filter != null && filter.getValue() != PdfName.standard.getValue()) {
      throw PdfException(
          KernelExceptionMessageConstant.noCompatibleEncryptionFound);
    }
    final version = (await pdfDict.numberEntry(PdfName.v))?.intValue() ?? 0;
    final revision = (await pdfDict.numberEntry(PdfName.r))?.intValue() ?? 2;
    final declaredLength =
        (await pdfDict.numberEntry(PdfName.length))?.intValue() ??
            defaultKeyLength;
    _encryptMetadata =
        (await pdfDict.booleanEntry(PdfName.encryptMetadata))?.getValue() ??
            true;

    CryptFilterConfiguration configuration;
    CryptFilterMethod method;
    int keyLengthBits;

    if (version >= 4) {
      configuration =
          await CryptFilterConfiguration.fromEncryptionDictionary(pdfDict);
      final active = configuration.streamFilter.isIdentity
          ? (configuration.stringFilter.isIdentity
              ? configuration.embeddedFileFilter
              : configuration.stringFilter)
          : configuration.streamFilter;
      method = active.method;
      keyLengthBits = active.keyLengthInBits(declaredLength);
      _embeddedFilesOnly = configuration.streamFilter.isIdentity &&
          configuration.stringFilter.isIdentity &&
          !configuration.embeddedFileFilter.isIdentity;
      if (!active.encryptMetadata) _encryptMetadata = false;
    } else {
      method = CryptFilterMethod.v2;
      keyLengthBits = version <= 1 ? 40 : declaredLength;
      configuration = CryptFilterConfiguration.uniform(CryptFilter(
          name: PdfName.stdCF,
          method: CryptFilterMethod.v2,
          length: keyLengthBits));
    }
    if (keyLengthBits < 40 || keyLengthBits > 256 || keyLengthBits % 8 != 0) {
      throw PdfException.withParams(
          KernelExceptionMessageConstant.unknownEncryptionTypeV, [version]);
    }

    SecurityHandler handler;
    if (version == 5 || method == CryptFilterMethod.aesV3) {
      if (revision != 5 && revision != 6) {
        throw PdfException.withParams(
            KernelExceptionMessageConstant.unknownEncryptionTypeR, [revision]);
      }
      final aes = await StandardHandlerUsingAes256.fromDictionary(
          pdfDict, password);
      _encryptMetadata = aes.isEncryptMetadata();
      handler = aes;
      _cryptoMode = EncryptionConstants.encryptionAes256;
    } else if (method == CryptFilterMethod.aesV2) {
      final aes = StandardHandlerUsingAes128.read(
          pdfDict, password, documentId, _encryptMetadata,
          keyLength: keyLengthBits);
      await aes.initForReading(pdfDict, password, documentId);
      handler = aes;
      _cryptoMode = EncryptionConstants.encryptionAes128;
    } else if (revision >= 3) {
      final rc4 = StandardHandlerUsingStandard128.read(
          pdfDict, password, documentId, _encryptMetadata,
          keyLength: keyLengthBits);
      await rc4.initForReading(pdfDict, password, documentId);
      handler = rc4;
      _cryptoMode = EncryptionConstants.standardEncryption128;
    } else if (revision == 2) {
      final rc4 = StandardHandlerUsingStandard40.read(
          pdfDict, password, documentId, _encryptMetadata,
          keyLength: 40);
      await rc4.initForReading(pdfDict, password, documentId);
      handler = rc4;
      _cryptoMode = EncryptionConstants.standardEncryption40;
    } else {
      throw PdfException.withParams(
          KernelExceptionMessageConstant.unknownEncryptionTypeR, [revision]);
    }

    if (!_encryptMetadata) {
      _cryptoMode |= EncryptionConstants.doNotEncryptMetadata;
    }
    _securityHandler = handler;
    if (handler is StandardSecurityHandler) {
      _permissions = handler.getPermissions();
    }
    _cryptFilters = version >= 4
        ? configuration
        : _configurationFor(_cryptoMode & EncryptionConstants.encryptionMask,
            _encryptMetadata, _embeddedFilesOnly);
  }

  static CryptFilterConfiguration _configurationFor(
      int mode, bool encryptMetadata, bool embeddedFilesOnly) {
    CryptFilterMethod method;
    int bits;
    switch (mode) {
      case EncryptionConstants.standardEncryption40:
        method = CryptFilterMethod.v2;
        bits = 40;
        break;
      case EncryptionConstants.standardEncryption128:
        method = CryptFilterMethod.v2;
        bits = 128;
        break;
      case EncryptionConstants.encryptionAes256:
        method = CryptFilterMethod.aesV3;
        bits = 256;
        break;
      default:
        method = CryptFilterMethod.aesV2;
        bits = 128;
        break;
    }
    final filter = CryptFilter(
      name: PdfName.stdCF,
      method: method,
      length: bits,
      authEvent: embeddedFilesOnly ? PdfName.efOpen : PdfName.docOpen,
      encryptMetadata: encryptMetadata,
    );
    if (!embeddedFilesOnly) return CryptFilterConfiguration.uniform(filter);
    return CryptFilterConfiguration(
      filters: {filter.name.getValue(): filter},
      streamFilter: CryptFilter.identity,
      stringFilter: CryptFilter.identity,
      embeddedFileFilter: filter,
    );
  }

  static Uint8List generateNewDocumentId() {
    final sha512 = DigestAlgorithms.getMessageDigest("SHA-512");
    final time = SystemUtil.getTimeBasedSeed();
    final mem = SystemUtil.getFreeMemory();
    final s = "$time+$mem+${_seq++}";
    return sha512.digestWithInput(EncodingUtil.convertToBytes(s, "ISO-8859-1"));
  }

  @override
  bool requiresIndirectStorage() => true;

  int getEncryptionAlgorithm() {
    return _cryptoMode & EncryptionConstants.encryptionMask;
  }

  /// The combined crypto mode, including the metadata and embedded-file flags.
  int getCryptoMode() => _cryptoMode;

  bool isMetadataEncrypted() => _encryptMetadata;

  bool isEmbeddedFilesOnly() => _embeddedFilesOnly;

  Uint8List? getDocumentId() => _documentId;

  int? getPermissions() => _permissions;

  /// Whether the password supplied when reading was the owner password.
  bool isOwnerPasswordUsed() {
    final handler = _securityHandler;
    return handler is StandardSecurityHandler
        ? handler.isUsedOwnerPassword()
        : true;
  }

  /// The file encryption key computed by the security handler.
  Uint8List getFileEncryptionKey() =>
      Uint8List.fromList(_securityHandler?.getMkey() ?? Uint8List(0));

  /// The resolved `/CF`, `/StmF`, `/StrF` and `/EFF` configuration.
  CryptFilterConfiguration? getCryptFilters() => _cryptFilters;

  void setSecurityHandler(SecurityHandler securityHandler) {
    _securityHandler = securityHandler;
  }

  SecurityHandler? getSecurityHandler() {
    return _securityHandler;
  }

  /// Records the identifier of the indirect object about to be written or
  /// read, as required by "Algorithm 1", step (a).
  void setHashKeyForNextObject(int objNumber, int objGeneration) {
    _objectNumber = objNumber;
    _generation = objGeneration;
    _securityHandler?.setHashKeyForNextObject(objNumber, objGeneration);
  }

  /// Marks whether the object being written belongs to an object stream.
  ///
  /// 7.5.7: "In an encrypted file (i.e., entire object stream is encrypted),
  /// strings occurring anywhere in an object stream shall not be separately
  /// encrypted."
  void setInObjectStream(bool inObjectStream) {
    _inObjectStream = inObjectStream;
  }

  bool isInObjectStream() => _inObjectStream;

  /// Whether [object] is the encryption dictionary itself, whose contents
  /// 7.6.1 leaves unencrypted.
  bool isEncryptionDictionary(Object? object) =>
      identical(object, pdfRepresentation());

  OutputStreamEncryption? getEncryptionStream(dynamic os) {
    return _securityHandler?.getEncryptionStream(os);
  }

  Uint8List encryptByteArray(Uint8List data) {
    if (_securityHandler == null) {
      return data;
    }
    final buffer = BytesBuilder();
    final encStream = _securityHandler!.getEncryptionStream(buffer);
    encStream.write(data);
    encStream.finish();
    return buffer.toBytes();
  }

  /// Decrypts data previously produced by [encryptByteArray] for the object
  /// recorded by [setHashKeyForNextObject].
  Uint8List decryptByteArray(Uint8List data) {
    final handler = _securityHandler;
    if (handler == null) return data;
    final decryptor = handler.getDecryptor();
    final head = decryptor.update(data, 0, data.length) ?? Uint8List(0);
    final tail = decryptor.finish() ?? Uint8List(0);
    final result = Uint8List(head.length + tail.length);
    result.setRange(0, head.length, head);
    result.setRange(head.length, result.length, tail);
    return result;
  }

  CryptFilterCipher? _cipherFor(CryptFilter? filter) {
    final handler = _securityHandler;
    if (handler == null || filter == null) return null;
    return CryptFilterCipher(filter, handler.getMkey());
  }

  /// Encrypts a string with the filter named by `/StrF`.
  ///
  /// Strings inside an object stream and strings of the encryption dictionary
  /// are returned unchanged.
  Uint8List encryptString(Uint8List data,
      [int? objectNumber, int? generation]) {
    if (_inObjectStream) return Uint8List.fromList(data);
    final cipher = _cipherFor(_cryptFilters?.stringFilter);
    if (cipher == null) return Uint8List.fromList(data);
    return cipher.encrypt(
        data, objectNumber ?? _objectNumber, generation ?? _generation);
  }

  /// Decrypts a string with the filter named by `/StrF`.
  Uint8List decryptString(Uint8List data,
      [int? objectNumber, int? generation]) {
    if (_inObjectStream) return Uint8List.fromList(data);
    final cipher = _cipherFor(_cryptFilters?.stringFilter);
    if (cipher == null) return Uint8List.fromList(data);
    return cipher.decrypt(
        data, objectNumber ?? _objectNumber, generation ?? _generation);
  }

  /// Resolves the filter that applies to a stream.
  ///
  /// [cryptFilterName] is the `/Name` of a Crypt filter decode parameters
  /// dictionary (Table 14); when present it overrides the document default.
  /// [isEmbeddedFile] selects `/EFF`, and [isMetadata] honours the
  /// `/EncryptMetadata` flag of Table 21.
  CryptFilter streamFilterFor(
      {PdfName? cryptFilterName,
      bool isEmbeddedFile = false,
      bool isMetadata = false}) {
    final filters = _cryptFilters;
    if (filters == null) return CryptFilter.identity;
    if (cryptFilterName != null) {
      return filters.byName(cryptFilterName) ?? CryptFilter.identity;
    }
    if (isMetadata && !_encryptMetadata) return CryptFilter.identity;
    if (isEmbeddedFile) return filters.embeddedFileFilter;
    return filters.streamFilter;
  }

  /// Encrypts stream data after all stream encoding filters have been applied.
  Uint8List encryptStream(Uint8List data, int objectNumber, int generation,
      {PdfName? cryptFilterName,
      bool isEmbeddedFile = false,
      bool isMetadata = false}) {
    final filter = streamFilterFor(
        cryptFilterName: cryptFilterName,
        isEmbeddedFile: isEmbeddedFile,
        isMetadata: isMetadata);
    final cipher = _cipherFor(filter);
    if (cipher == null) return Uint8List.fromList(data);
    return cipher.encrypt(data, objectNumber, generation);
  }

  /// Decrypts stream data before any stream decoding filter is applied.
  Uint8List decryptStream(Uint8List data, int objectNumber, int generation,
      {PdfName? cryptFilterName,
      bool isEmbeddedFile = false,
      bool isMetadata = false}) {
    final filter = streamFilterFor(
        cryptFilterName: cryptFilterName,
        isEmbeddedFile: isEmbeddedFile,
        isMetadata: isMetadata);
    final cipher = _cipherFor(filter);
    if (cipher == null) return Uint8List.fromList(data);
    return cipher.decrypt(data, objectNumber, generation);
  }
}
