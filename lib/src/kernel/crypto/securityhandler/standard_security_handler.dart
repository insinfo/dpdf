import 'dart:typed_data';

import 'package:dpdf/src/io/source/byte_utils.dart';
import 'package:dpdf/src/kernel/crypto/digest_algorithms.dart';
import 'package:dpdf/src/kernel/pdf/pdf_encryption.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/security_handler.dart';
import 'package:dpdf/src/kernel/exceptions/kernel_exception_message_constant.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_literal.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

/// Base class for standard security handlers.
abstract class StandardSecurityHandler extends SecurityHandler {
  static const int permsMask1ForRevision2 = 0xffffffc0;
  static const int permsMask1ForRevision3OrGreater = 0xffffe0c0;
  static const int permsMask2 = 0xfffffffc;

  int permissions = 0;
  bool usedOwnerPassword = true;

  int getPermissions() => permissions;

  /// Updates encryption dictionary with the security permissions provided.
  void setPermissions(int permissions, PdfDictionary encryptionDictionary) {
    this.permissions = permissions;
    encryptionDictionary.put(PdfName.p, PdfNumber.fromInt(permissions));
  }

  bool isUsedOwnerPassword() => usedOwnerPassword;

  void setStandardHandlerDicEntries(PdfDictionary encryptionDictionary,
      Uint8List userKey, Uint8List ownerKey) {
    encryptionDictionary.put(PdfName.filter, PdfName.standard);
    encryptionDictionary.put(PdfName.o, PdfLiteral.fromBytes(ownerKey));
    encryptionDictionary.put(PdfName.u, PdfLiteral.fromBytes(userKey));
    encryptionDictionary.put(PdfName.p, PdfNumber.fromInt(permissions));
  }

  Uint8List generateOwnerPasswordIfNullOrEmpty(Uint8List? ownerPassword) {
    if (ownerPassword == null || ownerPassword.isEmpty) {
      try {
        final sha256 = DigestAlgorithms.getMessageDigest("SHA-256");
        ownerPassword =
            sha256.digestWithInput(PdfEncryption.generateNewDocumentId());
      } catch (e) {
        throw PdfException(KernelExceptionMessageConstant.unknownPdfException,
            cause: e);
      }
    }
    return ownerPassword;
  }

  Uint8List getIsoBytes(PdfString string) {
    return ByteUtils.getIsoBytes(string.getValue());
  }

  bool equalsArray(Uint8List ar1, Uint8List ar2, int size) {
    for (int k = 0; k < size; ++k) {
      if (ar1[k] != ar2[k]) {
        return false;
      }
    }
    return true;
  }

  void setSpecificHandlerDicEntries(PdfDictionary encryptionDictionary,
      bool encryptMetadata, bool embeddedFilesOnly) {}
}
