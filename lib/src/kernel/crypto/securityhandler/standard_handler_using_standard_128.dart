import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/securityhandler/standard_handler_using_standard_40.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_security_handler.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';

/// The revision 3 and 4 standard security handler, using RC4 with a key whose
/// length comes from the `/Length` entry (ISO 32000-1:2008, 7.6.3).
class StandardHandlerUsingStandard128 extends StandardHandlerUsingStandard40 {
  StandardHandlerUsingStandard128(
      super.encryptionDictionary,
      super.userPassword,
      super.ownerPassword,
      super.permissions,
      super.encryptMetadata,
      super.embeddedFilesOnly,
      super.documentId,
      {super.keyLength = 128});

  StandardHandlerUsingStandard128.read(super.encryptionDictionary,
      super.password, super.documentId, super.encryptMetadata,
      {super.keyLength = 128})
      : super.read();

  /// "Algorithm 6", step (b): revisions 3 and greater compare the first 16
  /// bytes only, because "Algorithm 5" appends 16 bytes of arbitrary padding.
  @override
  int get userKeyComparisonLength => 16;

  @override
  void calculatePermissions(int permissions) {
    permissions |= StandardSecurityHandler.permsMask1ForRevision3OrGreater;
    permissions &= StandardSecurityHandler.permsMask2;
    this.permissions = permissions;
  }

  /// "Algorithm 3", with the 50 extra MD5 rounds of step (c) and the 20 RC4
  /// invocations of step (g).
  @override
  Uint8List computeOwnerKey(Uint8List userPad, Uint8List ownerPad) {
    final ownerKey = Uint8List(32);
    final mkeyLen = keyLength ~/ 8;
    final digest = computeOwnerPasswordKey(ownerPad);

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

  /// Steps (a) to (d) of "Algorithm 3" for revisions 3 and greater.
  @override
  Uint8List computeOwnerPasswordKey(Uint8List ownerPad) {
    final mkeyLen = keyLength ~/ 8;
    Uint8List digest = md5.digestWithInput(ownerPad);
    for (int k = 0; k < 50; ++k) {
      md5.reset();
      md5.update(digest, 0, mkeyLen);
      digest = md5.digest();
    }
    return Uint8List.fromList(digest.sublist(0, mkeyLen));
  }

  /// Step (b) of "Algorithm 7" for revisions 3 and greater: 20 RC4 passes with
  /// the key XORed against the iteration counter, from 19 down to 0.
  @override
  Uint8List recoverUserPasswordPad(Uint8List oValue, Uint8List key) {
    final recovered = Uint8List(32);
    recovered.setRange(0, 32, oValue);
    final iterationKey = Uint8List(key.length);
    for (int i = 19; i >= 0; --i) {
      for (int j = 0; j < key.length; ++j) {
        iterationKey[j] = (key[j] ^ i) & 0xFF;
      }
      arcfour.prepareARCFOURKey(iterationKey);
      arcfour.encryptARCFOURInPlace(recovered);
    }
    return recovered;
  }

  /// "Algorithm 2" with the 50 rehash rounds of step (h).
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

  /// "Algorithm 5: Computing the encryption dictionary's U (user password)
  /// value (Security handlers of revision 3 or greater)".
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
    // Step (f): the last 16 bytes are arbitrary padding, left as zeroes.

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
      // Table 21: /EncryptMetadata is meaningful only when /V is 4, so keeping
      // the metadata in plaintext forces the crypt filter form.
      encryptionDictionary.put(PdfName.encryptMetadata, PdfBoolean.pdfFalse);
      encryptionDictionary.put(PdfName.r, PdfNumber.fromInt(4));
      encryptionDictionary.put(PdfName.v, PdfNumber.fromInt(4));

      final stdcf = PdfDictionary();
      stdcf.put(PdfName.length, PdfNumber.fromInt(keyLength ~/ 8));
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
