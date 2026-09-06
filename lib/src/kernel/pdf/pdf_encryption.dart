import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/securityhandler/standard_handler_using_standard_40.dart';

import 'package:dpdf/src/commons/utils/encoding_util.dart';
import 'package:dpdf/src/commons/utils/system_util.dart';
import 'package:dpdf/src/kernel/crypto/digest_algorithms.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_encryption.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/security_handler.dart';
import 'package:dpdf/src/kernel/pdf/encryption_constants.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';

/// Class responsible for PDF encryption.
class PdfEncryption extends PdfObjectWrapper<PdfDictionary> {
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

  PdfEncryption() : super(PdfDictionary());

  /// Creates a PdfEncryption instance based on already existing standard encryption dictionary.
  PdfEncryption.fromDictionary(
      PdfDictionary pdfDict, Uint8List password, Uint8List documentId)
      : super(pdfDict) {
    setForbidRelease();
    this._documentId = documentId;
    _readAndSetCryptoModeForStdHandler(pdfDict, password, documentId);
  }

  /// Async factory to create and initialize PdfEncryption.
  static Future<PdfEncryption> createFromDictionary(
      PdfDictionary pdfDict, Uint8List password, Uint8List documentId) async {
    final encryption =
        PdfEncryption.fromDictionary(pdfDict, password, documentId);
    final handler = encryption.getSecurityHandler();
    if (handler is StandardHandlerUsingStandard40) {
      await handler.initForReading(pdfDict, password, documentId);
    }
    return encryption;
  }

  void _readAndSetCryptoModeForStdHandler(
      PdfDictionary pdfDict, Uint8List password, Uint8List documentId) {
    // This is a simplified version. For full implementation we need to check /V and /R
    // and potentially create different handlers (Standard, PublicKey, etc.)
    // For now, defaulting to StandardHandlerUsingStandard40 if we can't determine better,
    // or arguably we should defer creation until we read /V /R properly.

    // In strict C# port, this logic is quite complex and async-unfriendly in constructor.
    // For this pass, I will create a StandardHandlerUsingStandard40
    // which effectively acts as a "try to decrypt with standard 40"
    // TODO: Handle V=4 (AES), V=5 (AES-256) and pub key handlers

    _securityHandler = StandardHandlerUsingStandard40.read(
        pdfDict, password, documentId, _encryptMetadata);
  }

  static Uint8List generateNewDocumentId() {
    final sha512 = DigestAlgorithms.getMessageDigest("SHA-512");
    final time = SystemUtil.getTimeBasedSeed();
    final mem = SystemUtil.getFreeMemory();
    final s = "$time+$mem+${_seq++}";
    return sha512.digestWithInput(EncodingUtil.convertToBytes(s, "ISO-8859-1"));
  }

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  int getEncryptionAlgorithm() {
    return _cryptoMode & EncryptionConstants.encryptionMask;
  }

  bool isMetadataEncrypted() => _encryptMetadata;

  bool isEmbeddedFilesOnly() => _embeddedFilesOnly;

  Uint8List? getDocumentId() => _documentId;

  int? getPermissions() => _permissions;

  void setSecurityHandler(SecurityHandler securityHandler) {
    _securityHandler = securityHandler;
  }

  SecurityHandler? getSecurityHandler() {
    return _securityHandler;
  }

  void setHashKeyForNextObject(int objNumber, int objGeneration) {
    _securityHandler?.setHashKeyForNextObject(objNumber, objGeneration);
  }

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
}
