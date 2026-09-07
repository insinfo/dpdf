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
abstract class CraftStandardSecurityHandler extends CraftSecurityHandler {
  static const int permsMask1ForRevision2 = 0xffffffc0;
  static const int permsMask1ForRevision3OrGreater = 0xffffe0c0;
  static const int permsMask2 = 0xfffffffc;

  int permissions = 0;
  bool usedOwnerPassword = true;

  int getPermissions() => permissions;

  /// Updates encryption dictionary with the security permissions provided.
  void setPermissions(
      int permissions, CraftPdfDictionary encryptionDictionary) {
    this.permissions = permissions;
    encryptionDictionary.put(
        CraftPdfName.p, CraftPdfNumber.fromInt(permissions));
  }

  bool isUsedOwnerPassword() => usedOwnerPassword;

  void setStandardHandlerDicEntries(CraftPdfDictionary encryptionDictionary,
      Uint8List userKey, Uint8List ownerKey) {
    encryptionDictionary.put(CraftPdfName.filter, CraftPdfName.standard);
    encryptionDictionary.put(
        CraftPdfName.o, CraftPdfLiteral.fromBytes(ownerKey));
    encryptionDictionary.put(
        CraftPdfName.u, CraftPdfLiteral.fromBytes(userKey));
    encryptionDictionary.put(
        CraftPdfName.p, CraftPdfNumber.fromInt(permissions));
  }

  Uint8List generateOwnerPasswordIfNullOrEmpty(Uint8List? ownerPassword) {
    if (ownerPassword == null || ownerPassword.isEmpty) {
      try {
        final sha256 = CraftDigestAlgorithms.getMessageDigest("SHA-256");
        ownerPassword =
            sha256.digestWithInput(CraftPdfEncryption.generateNewDocumentId());
      } catch (e) {
        throw CraftPdfException(
            CraftKernelExceptionMessageConstant.unknownPdfException,
            cause: e);
      }
    }
    return ownerPassword;
  }

  Uint8List getIsoBytes(CraftPdfString string) {
    return CraftByteUtils.getIsoBytes(string.getValue());
  }

  bool equalsArray(Uint8List ar1, Uint8List ar2, int size) {
    RangeError.checkValidRange(0, size, ar1.length);
    RangeError.checkValidRange(0, size, ar2.length);
    var mismatch = 0;
    for (var offset = size; offset > 0;) {
      offset -= 1;
      mismatch |= ar1[offset] ^ ar2[offset];
    }
    return mismatch == 0;
  }

  void setSpecificHandlerDicEntries(CraftPdfDictionary encryptionDictionary,
      bool encryptMetadata, bool embeddedFilesOnly) {}
}
