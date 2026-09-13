import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/digest_algorithms.dart';
import 'package:dpdf/src/kernel/pdf/pdf_encryption.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/security_handler.dart';
import 'package:dpdf/src/kernel/exceptions/kernel_exception_message_constant.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

/// Base class for the standard security handler of ISO 32000-1:2008, 7.6.3.
abstract class StandardSecurityHandler extends SecurityHandler {
  /// Bits 7, 8 and 13 to 32 of Table 22 are reserved and shall be 1 for
  /// security handlers of revision 2.
  static const int permsMask1ForRevision2 = 0xffffffc0;

  /// Revision 3 and greater additionally define bits 9 to 12.
  static const int permsMask1ForRevision3OrGreater = 0xffffe0c0;

  /// Bits 1 and 2 are reserved and shall be 0.
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

  /// Writes `/Filter`, `/O`, `/U` and `/P` (Tables 20 and 21).
  ///
  /// `/O` and `/U` hold arbitrary binary data, so they are written in
  /// hexadecimal form; 7.6.1 requires the strings of an encryption dictionary
  /// to be direct objects and leaves their contents unencrypted.
  void setStandardHandlerDicEntries(PdfDictionary encryptionDictionary,
      Uint8List userKey, Uint8List ownerKey) {
    encryptionDictionary.put(PdfName.filter, PdfName.standard);
    encryptionDictionary.put(PdfName.o, PdfString.fromBytes(ownerKey, true));
    encryptionDictionary.put(PdfName.u, PdfString.fromBytes(userKey, true));
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
    return string.getValueBytes() ?? Uint8List(0);
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

  void setSpecificHandlerDicEntries(PdfDictionary encryptionDictionary,
      bool encryptMetadata, bool embeddedFilesOnly) {}
}
