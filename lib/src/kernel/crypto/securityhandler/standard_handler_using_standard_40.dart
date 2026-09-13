import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/arcfour_encryption.dart';
import 'package:dpdf/src/kernel/crypto/decryptor.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_encryption.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_standard_encryption.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_security_handler.dart';
import 'package:dpdf/src/kernel/crypto/standard_decryptor.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/exceptions/kernel_exception_message_constant.dart';

/// The revision 2 standard security handler of ISO 32000-1:2008, 7.6.3.
///
/// The class also carries the parts of "Algorithm 2" through "Algorithm 7"
/// that revisions 3 and greater reuse; [StandardHandlerUsingStandard128]
/// overrides the steps those revisions change.
class StandardHandlerUsingStandard40 extends StandardSecurityHandler {
  /// The 32-byte padding string of "Algorithm 2", step (a).
  static final Uint8List pad = Uint8List.fromList([
    0x28,
    0xBF,
    0x4E,
    0x5E,
    0x4E,
    0x75,
    0x8A,
    0x41,
    0x64,
    0x00,
    0x4E,
    0x56,
    0xFF,
    0xFA,
    0x01,
    0x08,
    0x2E,
    0x2E,
    0x00,
    0xB6,
    0xD0,
    0x68,
    0x3E,
    0x80,
    0x2F,
    0x0C,
    0xA9,
    0xFE,
    0x64,
    0x53,
    0x69,
    0x7A
  ]);

  /// The four bytes of "Algorithm 2", step (f), hashed when the document
  /// metadata is not encrypted.
  static final Uint8List metadataPad = Uint8List.fromList([255, 255, 255, 255]);

  Uint8List? documentId;
  int keyLength = 40;
  final ARCFOUREncryption arcfour = ARCFOUREncryption();

  static const int defaultKeyLengthValue = 40;

  bool _encryptMetadata = true;

  StandardHandlerUsingStandard40(
      PdfDictionary encryptionDictionary,
      Uint8List? userPassword,
      Uint8List? ownerPassword,
      int permissions,
      bool encryptMetadata,
      bool embeddedFilesOnly,
      Uint8List? documentId,
      {this.keyLength = defaultKeyLengthValue}) {
    _encryptMetadata = encryptMetadata;
    _initKeyAndFillDictionary(encryptionDictionary, userPassword, ownerPassword,
        permissions, encryptMetadata, embeddedFilesOnly, documentId);
  }

  StandardHandlerUsingStandard40.read(PdfDictionary encryptionDictionary,
      Uint8List password, this.documentId, bool encryptMetadata,
      {this.keyLength = defaultKeyLengthValue}) {
    _encryptMetadata = encryptMetadata;
  }

  /// Whether the document metadata stream is covered by the encryption.
  bool isEncryptMetadata() => _encryptMetadata;

  /// The number of leading `/U` bytes "Algorithm 6" compares.
  ///
  /// Revision 2 stores the whole 32-byte result; revisions 3 and greater
  /// append 16 bytes of arbitrary padding, so only the first 16 are checked.
  int get userKeyComparisonLength => 32;

  /// Authenticates a password against `/O` and `/U`, per "Algorithm 6:
  /// Authenticating the user password" and "Algorithm 7: Authenticating the
  /// owner password".
  Future<void> initForReading(PdfDictionary encryptionDictionary,
      Uint8List password, Uint8List? documentId) async {
    final oObj = await encryptionDictionary.stringEntry(PdfName.o);
    final uObj = await encryptionDictionary.stringEntry(PdfName.u);
    final pObj = await encryptionDictionary.numberEntry(PdfName.p);

    if (oObj == null || uObj == null || pObj == null) {
      throw PdfException(
          KernelExceptionMessageConstant.standardHandlerBadDictionary);
    }

    final oValue = oObj.getValueBytes();
    final uValue = uObj.getValueBytes();

    permissions = pObj.intValue();
    this.documentId = documentId;

    if (oValue == null || uValue == null || oValue.length < 32 ||
        uValue.length < userKeyComparisonLength) {
      throw PdfException(
          KernelExceptionMessageConstant.standardHandlerBadDictionary);
    }

    // "Algorithm 6": try the supplied password as the user password.
    computeGlobalEncryptionKey(
        padPassword(password), oValue, _encryptMetadata);
    if (_matchesUserKey(uValue)) {
      usedOwnerPassword = false;
      return;
    }

    // "Algorithm 7": recover the user password from /O and retry.
    final ownerKey = computeOwnerPasswordKey(padPassword(password));
    final recoveredUserPad = recoverUserPasswordPad(oValue, ownerKey);
    computeGlobalEncryptionKey(recoveredUserPad, oValue, _encryptMetadata);
    if (_matchesUserKey(uValue)) {
      usedOwnerPassword = true;
      return;
    }

    throw BadPasswordException(KernelExceptionMessageConstant.badUserPassword);
  }

  bool _matchesUserKey(Uint8List uValue) {
    if (mkey.isEmpty) return false;
    return equalsArray(computeUserKey(), uValue, userKeyComparisonLength);
  }

  /// Steps (a) to (d) of "Algorithm 3": the RC4 key derived from the padded
  /// owner password.
  Uint8List computeOwnerPasswordKey(Uint8List ownerPad) {
    final digest = md5.digestWithInput(ownerPad);
    return Uint8List.fromList(digest.sublist(0, 5));
  }

  /// Step (b) of "Algorithm 7": revision 2 decrypts `/O` once.
  Uint8List recoverUserPasswordPad(Uint8List oValue, Uint8List key) {
    final recovered = Uint8List(32);
    arcfour.prepareARCFOURKey(key);
    arcfour.encryptARCFOUR(oValue, 0, 32, recovered, 0);
    return recovered;
  }

  @override
  OutputStreamEncryption getEncryptionStream(dynamic os) {
    return OutputStreamStandardEncryption(
        os, nextObjectKey!, 0, nextObjectKeySize);
  }

  @override
  Decryptor getDecryptor() {
    return StandardDecryptor(nextObjectKey!, 0, nextObjectKeySize);
  }

  void _initKeyAndFillDictionary(
      PdfDictionary encryptionDictionary,
      Uint8List? userPassword,
      Uint8List? ownerPassword,
      int permissions,
      bool encryptMetadata,
      bool embeddedFilesOnly,
      Uint8List? documentId) {
    ownerPassword = generateOwnerPasswordIfNullOrEmpty(ownerPassword);
    calculatePermissions(permissions);
    this.documentId = documentId;

    final userPad = padPassword(userPassword);
    final ownerPad = padPassword(ownerPassword);
    final ownerKey = computeOwnerKey(userPad, ownerPad);
    computeGlobalEncryptionKey(userPad, ownerKey, encryptMetadata);
    final userKey = computeUserKey();

    setStandardHandlerDicEntries(encryptionDictionary, userKey, ownerKey);
    setSpecificHandlerDicEntries(
        encryptionDictionary, encryptMetadata, embeddedFilesOnly);
  }

  void calculatePermissions(int permissions) {
    permissions |= StandardSecurityHandler.permsMask1ForRevision2;
    permissions &= StandardSecurityHandler.permsMask2;
    this.permissions = permissions;
  }

  /// "Algorithm 3: Computing the encryption dictionary's O (owner password)
  /// value".
  Uint8List computeOwnerKey(Uint8List userPad, Uint8List ownerPad) {
    final ownerKey = Uint8List(32);
    final digest = md5.digestWithInput(ownerPad);
    arcfour.prepareARCFOURKey(digest, 0, 5);
    arcfour.encryptARCFOURAll(userPad, ownerKey);
    return ownerKey;
  }

  /// "Algorithm 2: Computing an encryption key", steps (b) to (i) for
  /// revision 2.
  void computeGlobalEncryptionKey(
      Uint8List userPad, Uint8List ownerKey, bool encryptMetadata) {
    mkey = Uint8List(keyLength ~/ 8);
    md5.reset();
    md5.updateAll(userPad);
    md5.updateAll(ownerKey);
    final ext = Uint8List(4);
    ext[0] = permissions & 0xFF;
    ext[1] = (permissions >> 8) & 0xFF;
    ext[2] = (permissions >> 16) & 0xFF;
    ext[3] = (permissions >> 24) & 0xFF;
    md5.updateAll(ext);

    if (documentId != null) {
      md5.updateAll(documentId!);
    }
    if (!encryptMetadata) {
      md5.updateAll(metadataPad);
    }

    final fullDigest = md5.digest();
    mkey.setRange(0, mkey.length, fullDigest);
  }

  /// "Algorithm 4: Computing the encryption dictionary's U (user password)
  /// value (Security handlers of revision 2)".
  Uint8List computeUserKey() {
    final userKey = Uint8List(32);
    arcfour.prepareARCFOURKey(mkey);
    arcfour.encryptARCFOURAll(pad, userKey);
    return userKey;
  }

  @override
  void setSpecificHandlerDicEntries(PdfDictionary encryptionDictionary,
      bool encryptMetadata, bool embeddedFilesOnly) {
    encryptionDictionary.put(PdfName.r, PdfNumber.fromInt(2));
    encryptionDictionary.put(PdfName.v, PdfNumber.fromInt(1));
  }

  /// "Algorithm 2", step (a): pad or truncate the password to 32 bytes.
  Uint8List padPassword(Uint8List? password) {
    final userPad = Uint8List(32);
    if (password == null) {
      userPad.setRange(0, 32, pad);
    } else {
      userPad.setRange(0, math.min(password.length, 32), password);
      if (password.length < 32) {
        userPad.setRange(password.length, 32, pad);
      }
    }
    return userPad;
  }
}
