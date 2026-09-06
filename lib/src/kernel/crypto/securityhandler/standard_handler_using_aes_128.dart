import 'dart:typed_data';

import 'package:pdfcraft/src/kernel/crypto/aes_decryptor.dart';
import 'package:pdfcraft/src/kernel/crypto/decryptor.dart';
import 'package:pdfcraft/src/kernel/crypto/output_stream_aes_encryption.dart';
import 'package:pdfcraft/src/kernel/crypto/output_stream_encryption.dart';
import 'package:pdfcraft/src/kernel/crypto/securityhandler/standard_handler_using_standard_128.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_boolean.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_dictionary.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_name.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_number.dart';

/// Standard security handler using AES-128 algorithm.
class CraftStandardHandlerUsingAes128
    extends CraftStandardHandlerUsingStandard128 {
  static final Uint8List salt =
      Uint8List.fromList([0x73, 0x41, 0x6c, 0x54]); // 'sAlT'

  CraftStandardHandlerUsingAes128(
      CraftPdfDictionary encryptionDictionary,
      Uint8List? userPassword,
      Uint8List? ownerPassword,
      int permissions,
      bool encryptMetadata,
      bool embeddedFilesOnly,
      Uint8List? documentId)
      : super(encryptionDictionary, userPassword, ownerPassword, permissions,
            encryptMetadata, embeddedFilesOnly, documentId);

  CraftStandardHandlerUsingAes128.read(CraftPdfDictionary encryptionDictionary,
      Uint8List password, Uint8List? documentId, bool encryptMetadata)
      : super.read(encryptionDictionary, password, documentId, encryptMetadata);

  @override
  CraftOutputStreamEncryption getEncryptionStream(dynamic os) {
    return CraftOutputStreamAesEncryption(
        os, nextObjectKey!, 0, nextObjectKeySize);
  }

  @override
  CraftDecryptor getDecryptor() {
    return CraftAesDecryptor(nextObjectKey!, 0, nextObjectKeySize);
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
  void setSpecificHandlerDicEntries(CraftPdfDictionary encryptionDictionary,
      bool encryptMetadata, bool embeddedFilesOnly) {
    if (!encryptMetadata) {
      encryptionDictionary.put(
          CraftPdfName.encryptMetadata, CraftPdfBoolean.pdfFalse);
    }
    encryptionDictionary.put(CraftPdfName.r, CraftPdfNumber.fromInt(4));
    encryptionDictionary.put(CraftPdfName.v, CraftPdfNumber.fromInt(4));

    final stdcf = CraftPdfDictionary();
    stdcf.put(CraftPdfName.length, CraftPdfNumber.fromInt(16));
    if (embeddedFilesOnly) {
      stdcf.put(CraftPdfName.authEvent, CraftPdfName.efOpen);
      encryptionDictionary.put(CraftPdfName.eff, CraftPdfName.stdCF);
      encryptionDictionary.put(CraftPdfName.strF, CraftPdfName.identity);
      encryptionDictionary.put(CraftPdfName.stmF, CraftPdfName.identity);
    } else {
      stdcf.put(CraftPdfName.authEvent, CraftPdfName.docOpen);
      encryptionDictionary.put(CraftPdfName.strF, CraftPdfName.stdCF);
      encryptionDictionary.put(CraftPdfName.stmF, CraftPdfName.stdCF);
    }
    stdcf.put(CraftPdfName.cfm, CraftPdfName.aesV2);

    final cf = CraftPdfDictionary();
    cf.put(CraftPdfName.stdCF, stdcf);
    encryptionDictionary.put(CraftPdfName.cf, cf);
  }
}
