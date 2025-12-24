import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/arcfour_encryption.dart';
import 'package:dpdf/src/kernel/crypto/i_decryptor.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_encryption.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_standard_encryption.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_security_handler.dart';
import 'package:dpdf/src/kernel/crypto/standard_decryptor.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';

/// Standard security handler using Standard 40 algorithm (RC4).
class StandardHandlerUsingStandard40 extends StandardSecurityHandler {
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

  static final Uint8List metadataPad = Uint8List.fromList([255, 255, 255, 255]);

  Uint8List? documentId;
  int keyLength = 40;
  final ARCFOUREncryption arcfour = ARCFOUREncryption();

  static const int defaultKeyLengthValue = 40;

  StandardHandlerUsingStandard40(
      PdfDictionary encryptionDictionary,
      Uint8List? userPassword,
      Uint8List? ownerPassword,
      int permissions,
      bool encryptMetadata,
      bool embeddedFilesOnly,
      Uint8List? documentId) {
    _initKeyAndFillDictionary(encryptionDictionary, userPassword, ownerPassword,
        permissions, encryptMetadata, embeddedFilesOnly, documentId);
  }

  StandardHandlerUsingStandard40.read(PdfDictionary encryptionDictionary,
      Uint8List password, Uint8List? documentId, bool encryptMetadata) {
    // TODO: implement read constructor
  }

  @override
  OutputStreamEncryption getEncryptionStream(dynamic os) {
    return OutputStreamStandardEncryption(
        os, nextObjectKey!, 0, nextObjectKeySize);
  }

  @override
  IDecryptor getDecryptor() {
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
    keyLength = _getKeyLength(encryptionDictionary);

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

  Uint8List computeOwnerKey(Uint8List userPad, Uint8List ownerPad) {
    final ownerKey = Uint8List(32);
    final digest = md5.digestWithInput(ownerPad);
    arcfour.prepareARCFOURKey(digest, 0, 5);
    arcfour.encryptARCFOURAll(userPad, ownerKey);
    return ownerKey;
  }

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

  int _getKeyLength(PdfDictionary encryptionDict) {
    // This is async in reality, but for now let's assume it's direct.
    // TODO: Fix this when dictionary handles sync access for known values.
    return defaultKeyLengthValue;
  }
}
