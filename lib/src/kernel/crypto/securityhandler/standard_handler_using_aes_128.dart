import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/aes_decryptor.dart';
import 'package:dpdf/src/kernel/crypto/i_decryptor.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_aes_encryption.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_encryption.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_handler_using_standard_128.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';

/// Standard security handler using AES-128 algorithm.
class StandardHandlerUsingAes128 extends StandardHandlerUsingStandard128 {
  static final Uint8List salt =
      Uint8List.fromList([0x73, 0x41, 0x6c, 0x54]); // 'sAlT'

  StandardHandlerUsingAes128(
      PdfDictionary encryptionDictionary,
      Uint8List? userPassword,
      Uint8List? ownerPassword,
      int permissions,
      bool encryptMetadata,
      bool embeddedFilesOnly,
      Uint8List? documentId)
      : super(encryptionDictionary, userPassword, ownerPassword, permissions,
            encryptMetadata, embeddedFilesOnly, documentId);

  StandardHandlerUsingAes128.read(PdfDictionary encryptionDictionary,
      Uint8List password, Uint8List? documentId, bool encryptMetadata)
      : super.read(encryptionDictionary, password, documentId, encryptMetadata);

  @override
  OutputStreamEncryption getEncryptionStream(dynamic os) {
    return OutputStreamAesEncryption(os, nextObjectKey!, 0, nextObjectKeySize);
  }

  @override
  IDecryptor getDecryptor() {
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
    stdcf.put(PdfName.cfm, PdfName.aesV2);

    final cf = PdfDictionary();
    cf.put(PdfName.stdCF, stdcf);
    encryptionDictionary.put(PdfName.cf, cf);
  }
}
