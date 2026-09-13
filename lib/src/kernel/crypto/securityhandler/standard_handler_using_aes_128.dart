import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/aes_decryptor.dart';
import 'package:dpdf/src/kernel/crypto/crypt_filter_cipher.dart';
import 'package:dpdf/src/kernel/crypto/decryptor.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_aes_encryption.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_encryption.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_handler_using_standard_128.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';

/// The revision 4 standard security handler using the `AESV2` crypt filter
/// method of ISO 32000-1:2008, Table 25.
class StandardHandlerUsingAes128 extends StandardHandlerUsingStandard128 {
  /// The `sAlT` suffix of "Algorithm 1", step (b).
  static final Uint8List salt = CryptFilterCipher.aesSalt;

  StandardHandlerUsingAes128(
      super.encryptionDictionary,
      super.userPassword,
      super.ownerPassword,
      super.permissions,
      super.encryptMetadata,
      super.embeddedFilesOnly,
      super.documentId,
      {super.keyLength = 128});

  StandardHandlerUsingAes128.read(super.encryptionDictionary, super.password,
      super.documentId, super.encryptMetadata,
      {super.keyLength = 128})
      : super.read();

  @override
  OutputStreamEncryption getEncryptionStream(dynamic os) {
    return OutputStreamAesEncryption(os, nextObjectKey!, 0, nextObjectKeySize);
  }

  @override
  Decryptor getDecryptor() {
    return AesDecryptor(nextObjectKey!, 0, nextObjectKeySize);
  }

  @override
  void setHashKeyForNextObject(int objNumber, int objGeneration) {
    md5.reset();
    extra[0] = objNumber & 0xFF;
    extra[1] = (objNumber >> 8) & 0xFF;
    extra[2] = (objNumber >> 16) & 0xFF;
    extra[3] = objGeneration & 0xFF;
    extra[4] = (objGeneration >> 8) & 0xFF;

    md5.updateAll(mkey);
    md5.updateAll(extra);
    md5.updateAll(salt);

    nextObjectKey = md5.digest();
    nextObjectKeySize = mkey.length + 5;
    if (nextObjectKeySize > 16) {
      nextObjectKeySize = 16;
    }
  }

  @override
  void setSpecificHandlerDicEntries(PdfDictionary encryptionDictionary,
      bool encryptMetadata, bool embeddedFilesOnly) {
    if (!encryptMetadata) {
      encryptionDictionary.put(PdfName.encryptMetadata, PdfBoolean.pdfFalse);
    }
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
    stdcf.put(PdfName.cfm, PdfName.aesV2);

    final cf = PdfDictionary();
    cf.put(PdfName.stdCF, stdcf);
    encryptionDictionary.put(PdfName.cf, cf);
  }
}
