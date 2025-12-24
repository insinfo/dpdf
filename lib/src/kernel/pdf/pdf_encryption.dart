import 'dart:typed_data';

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
    // TODO: Implement ReadAndSetCryptoModeForStdHandler and create specific security handler
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
}
