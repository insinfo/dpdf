import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/securityhandler/standard_handler_using_standard_40.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_security_handler.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';

/// Standard security handler using Standard 128 algorithm (RC4).
class StandardHandlerUsingStandard128 extends StandardHandlerUsingStandard40 {
  StandardHandlerUsingStandard128(
      PdfDictionary encryptionDictionary,
      Uint8List? userPassword,
      Uint8List? ownerPassword,
      int permissions,
      bool encryptMetadata,
      bool embeddedFilesOnly,
      Uint8List? documentId)
      : super(encryptionDictionary, userPassword, ownerPassword, permissions,
            encryptMetadata, embeddedFilesOnly, documentId);

  StandardHandlerUsingStandard128.read(PdfDictionary encryptionDictionary,
      Uint8List password, Uint8List? documentId, bool encryptMetadata)
      : super.read(encryptionDictionary, password, documentId, encryptMetadata);

  @override
  void calculatePermissions(int permissions) {
    permissions |= StandardSecurityHandler.permsMask1ForRevision3OrGreater;
    permissions &= StandardSecurityHandler.permsMask2;
    this.permissions = permissions;
  }

  @override
  Uint8List computeOwnerKey(Uint8List userPad, Uint8List ownerPad) {
    final ownerKey = Uint8List(32);
    Uint8List digest = md5.digestWithInput(ownerPad);
    final mkeyLen = keyLength ~/ 8;

    for (int k = 0; k < 50; ++k) {
      md5.reset();
      md5.update(digest, 0, mkeyLen);
      digest = md5.digest();
    }

    ownerKey.setRange(0, 32, userPad);
    final mkeyForArcfour = Uint8List(mkeyLen);
    for (int i = 0; i < 20; ++i) {
      for (int j = 0; j < mkeyLen; ++j) {
        mkeyForArcfour[j] = (digest[j] ^ i) & 0xFF;
      }
      arcfour.prepareARCFOURKey(mkeyForArcfour);
      arcfour.encryptARCFOURInPlace(ownerKey);
    }
    return ownerKey;
  }

  @override
  void computeGlobalEncryptionKey(
      Uint8List userPad, Uint8List ownerKey, bool encryptMetadata) {
    final mkeyLen = keyLength ~/ 8;
    mkey = Uint8List(mkeyLen);
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
      md5.updateAll(StandardHandlerUsingStandard40.metadataPad);
    }

    Uint8List digest = Uint8List(mkeyLen);
    digest.setRange(0, mkeyLen, md5.digest());

    for (int k = 0; k < 50; ++k) {
      md5.reset();
      md5.update(digest, 0, mkeyLen);
      digest.setRange(0, mkeyLen, md5.digest());
    }
    mkey.setRange(0, mkeyLen, digest);
  }

  @override
  Uint8List computeUserKey() {
    final userKey = Uint8List(32);
    md5.reset();
    md5.updateAll(StandardHandlerUsingStandard40.pad);
    if (documentId != null) {
      md5.updateAll(documentId!);
    }
    final digest = md5.digest();
    userKey.setRange(0, 16, digest);
    // bytes 16-31 are zeroes (already initialized in Uint8List)

    final mkeyLen = keyLength ~/ 8;
    final tempDigest = Uint8List(mkeyLen);
    for (int i = 0; i < 20; ++i) {
      for (int j = 0; j < mkeyLen; ++j) {
        tempDigest[j] = (mkey[j] ^ i) & 0xFF;
      }
      arcfour.prepareARCFOURKey(tempDigest, 0, mkeyLen);
      arcfour.encryptARCFOUR(userKey, 0, 16, userKey, 0);
    }
    return userKey;
  }

  @override
  void setSpecificHandlerDicEntries(PdfDictionary encryptionDictionary,
      bool encryptMetadata, bool embeddedFilesOnly) {
    if (encryptMetadata) {
      encryptionDictionary.put(PdfName.r, PdfNumber.fromInt(3));
      encryptionDictionary.put(PdfName.v, PdfNumber.fromInt(2));
    } else {
      encryptionDictionary.put(PdfName.encryptMetadata, PdfBoolean.pdfFalse);
      encryptionDictionary.put(PdfName.r, PdfNumber.fromInt(4));
      encryptionDictionary.put(PdfName.v, PdfNumber.fromInt(4));

      final stdcf = PdfDictionary();
      stdcf.put(PdfName.length, PdfNumber.fromInt(16));
      if (embeddedFilesOnly) {
        stdcf.put(PdfName.authEvent, PdfName.efOpen);
        encryptionDictionary.put(PdfName.eff, PdfName.stdCF);
        encryptionDictionary.put(PdfName.strF, PdfName.identity);
        encryptionDictionary.put(PdfName.stmF, PdfName.identity);
      } else {
        stdcf.put(PdfName.authEvent, PdfName.docOpen);
        encryptionDictionary.put(PdfName.strF, PdfName.stdCF);
        encryptionDictionary.put(PdfName.stmF, PdfName.stdCF);
      }
      stdcf.put(PdfName.cfm, PdfName.v2);
      final cf = PdfDictionary();
      cf.put(PdfName.stdCF, stdcf);
      encryptionDictionary.put(PdfName.cf, cf);
    }
  }

  bool isValidPassword(Uint8List uValue, Uint8List userKey) {
    return equalsArray(uValue, userKey, 16);
  }
}
