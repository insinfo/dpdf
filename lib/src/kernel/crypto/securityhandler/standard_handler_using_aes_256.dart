import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/aes_cipher.dart';
import 'package:dpdf/src/kernel/crypto/aes_decryptor.dart';
import 'package:dpdf/src/kernel/crypto/digest_algorithms.dart';
import 'package:dpdf/src/kernel/crypto/decryptor.dart';
import 'package:dpdf/src/kernel/crypto/iv_generator.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_aes_encryption.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_encryption.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/standard_security_handler.dart';
import 'package:dpdf/src/kernel/exceptions/kernel_exception_message_constant.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_version.dart';

/// The AES-256 standard security handler.
///
/// Revision 5 is the Adobe Extension Level 3 handler, whose password hash is
/// a single SHA-256 ("Algorithm 2.A" without the hardening loop). Revision 6
/// is the ISO 32000-2 handler, which runs the iterated hardening of
/// "Algorithm 2.B".
class StandardHandlerUsingAes256 extends StandardSecurityHandler {
  /// Offset of the validation salt inside the 48-byte `/O` and `/U` strings.
  static const int VALIDATION_SALT_OFFSET = 32;

  /// Offset of the key salt inside the 48-byte `/O` and `/U` strings.
  static const int KEY_SALT_OFFSET = 40;

  /// Length of both salts.
  static const int SALT_LENGTH = 8;

  bool _encryptMetadata = true;
  bool _revision6 = false;

  StandardHandlerUsingAes256(
      PdfDictionary encryptionDictionary,
      Uint8List? userPassword,
      Uint8List? ownerPassword,
      int permissions,
      bool encryptMetadata,
      bool embeddedFilesOnly,
      PdfVersion? version) {
    _revision6 = version != null && version.compareTo(PdfVersion.PDF_2_0) >= 0;
    _initKeyAndFillDictionary(encryptionDictionary, userPassword, ownerPassword,
        permissions, encryptMetadata, embeddedFilesOnly);
  }

  StandardHandlerUsingAes256._internal() : super();

  /// Reads an existing AES-256 encryption dictionary and authenticates
  /// [password] with "Algorithm 12" (owner) and "Algorithm 11" (user).
  static Future<StandardHandlerUsingAes256> fromDictionary(
      PdfDictionary encryptionDictionary, Uint8List password) async {
    final handler = StandardHandlerUsingAes256._internal();
    await handler._initKeyAndReadDictionary(encryptionDictionary, password);
    return handler;
  }

  bool isEncryptMetadata() => _encryptMetadata;

  /// Whether the handler runs the revision 6 hardening of "Algorithm 2.B".
  bool isRevision6() => _revision6;

  /// Prepares a password for hashing.
  ///
  /// ISO 32000-2 requires the password to be a UTF-8 encoding of the SASLprep
  /// profile of the supplied text, truncated to 127 bytes. The truncation and
  /// the UTF-8 encoding are applied here; the SASLprep mapping is left to the
  /// caller, which normally already holds UTF-8 bytes.
  static Uint8List preparePassword(Uint8List? password) {
    final bytes = password ?? Uint8List(0);
    return bytes.length > 127
        ? Uint8List.fromList(bytes.sublist(0, 127))
        : bytes;
  }

  /// Convenience wrapper encoding [password] as UTF-8 before truncation.
  static Uint8List preparePasswordString(String password) =>
      preparePassword(Uint8List.fromList(utf8.encode(password)));

  @override
  void setHashKeyForNextObject(int objNumber, int objGeneration) {
    // ISO 32000-2: the 256-bit file encryption key is used as is, so no
    // per-object derivation takes place.
  }

  @override
  OutputStreamEncryption getEncryptionStream(dynamic os) {
    return OutputStreamAesEncryption(os, nextObjectKey!, 0, nextObjectKeySize);
  }

  @override
  Decryptor getDecryptor() {
    return AesDecryptor(nextObjectKey!, 0, nextObjectKeySize);
  }

  @override
  void setPermissions(int permissions, PdfDictionary encryptionDictionary) {
    super.setPermissions(permissions, encryptionDictionary);
    final aes256Perms = getAes256Perms(permissions, isEncryptMetadata());
    encryptionDictionary.put(
        PdfName.perms, PdfString.fromBytes(aes256Perms, true));
  }

  void _initKeyAndFillDictionary(
      PdfDictionary encryptionDictionary,
      Uint8List? userPassword,
      Uint8List? ownerPassword,
      int permissions,
      bool encryptMetadata,
      bool embeddedFilesOnly) {
    ownerPassword = generateOwnerPasswordIfNullOrEmpty(ownerPassword);
    permissions |= StandardSecurityHandler.permsMask1ForRevision3OrGreater;
    permissions &= StandardSecurityHandler.permsMask2;

    try {
      final up = preparePassword(userPassword);
      final op = preparePassword(ownerPassword);

      final userValAndKeySalt = IVGenerator.getIVLen(16);
      final ownerValAndKeySalt = IVGenerator.getIVLen(16);
      nextObjectKey = IVGenerator.getIVLen(32);
      nextObjectKeySize = 32;
      mkey = Uint8List.fromList(nextObjectKey!);

      // "Algorithm 8", step 1: the /U string.
      final userValSalt = userValAndKeySalt.sublist(0, 8);
      final userKey = Uint8List(48);
      final hashUP = computeHash(up, userValSalt, null);
      userKey.setRange(0, 32, hashUP);
      userKey.setRange(32, 48, userValAndKeySalt);

      // "Algorithm 8", step 2: the /UE string.
      final userKeySalt = userValAndKeySalt.sublist(8, 16);
      final hashUPKey = computeHash(up, userKeySalt, null);
      final cipherUP =
          AESCipher(true, hashUPKey, Uint8List(16), usePadding: false);
      final ueKey =
          cipherUP.processBlock(nextObjectKey!, 0, nextObjectKey!.length);

      // "Algorithm 9", step 1: the /O string.
      final ownerValSalt = ownerValAndKeySalt.sublist(0, 8);
      final ownerKey = Uint8List(48);
      final hashOP = computeHash(op, ownerValSalt, userKey);
      ownerKey.setRange(0, 32, hashOP);
      ownerKey.setRange(32, 48, ownerValAndKeySalt);

      // "Algorithm 9", step 2: the /OE string.
      final ownerKeySalt = ownerValAndKeySalt.sublist(8, 16);
      final hashOPKey = computeHash(op, ownerKeySalt, userKey);
      final cipherOP =
          AESCipher(true, hashOPKey, Uint8List(16), usePadding: false);
      final oeKey =
          cipherOP.processBlock(nextObjectKey!, 0, nextObjectKey!.length);

      this.permissions = permissions;
      _encryptMetadata = encryptMetadata;

      // "Algorithm 10": the /Perms string.
      final aes256Perms = getAes256Perms(permissions, encryptMetadata);

      setStandardHandlerDicEntries(encryptionDictionary, userKey, ownerKey);
      _setAES256DicEntries(encryptionDictionary, oeKey, ueKey, aes256Perms,
          encryptMetadata, embeddedFilesOnly);
    } catch (e) {
      throw PdfException(KernelExceptionMessageConstant.unknownPdfException,
          cause: e);
    }
  }

  Future<void> _initKeyAndReadDictionary(
      PdfDictionary encryptionDictionary, Uint8List password) async {
    try {
      final pw = preparePassword(password);

      final revision =
          (await encryptionDictionary.numberEntry(PdfName.r))?.intValue() ?? 6;
      _revision6 = revision >= 6;

      final oEntry = await encryptionDictionary.stringEntry(PdfName.o);
      final uEntry = await encryptionDictionary.stringEntry(PdfName.u);
      final oeEntry = await encryptionDictionary.stringEntry(PdfName.oe);
      final ueEntry = await encryptionDictionary.stringEntry(PdfName.ue);
      final permsEntry = await encryptionDictionary.stringEntry(PdfName.perms);
      final pValue = await encryptionDictionary.numberEntry(PdfName.p);
      if (oEntry == null ||
          uEntry == null ||
          oeEntry == null ||
          ueEntry == null ||
          permsEntry == null ||
          pValue == null) {
        throw PdfException(
            KernelExceptionMessageConstant.standardHandlerBadDictionary);
      }

      final oValue = _truncateArray(getIsoBytes(oEntry));
      final uValue = _truncateArray(getIsoBytes(uEntry));
      final oeValue = getIsoBytes(oeEntry);
      final ueValue = getIsoBytes(ueEntry);
      final perms = getIsoBytes(permsEntry);
      permissions = pValue.intValue();

      // "Algorithm 12: Authenticating the owner password".
      final oValSalt = oValue.sublist(
          VALIDATION_SALT_OFFSET, VALIDATION_SALT_OFFSET + SALT_LENGTH);
      final hashPO = computeHash(pw, oValSalt, uValue);
      usedOwnerPassword = equalsArray(hashPO, oValue, 32);

      if (usedOwnerPassword) {
        final oKeySalt =
            oValue.sublist(KEY_SALT_OFFSET, KEY_SALT_OFFSET + SALT_LENGTH);
        final hashOK = computeHash(pw, oKeySalt, uValue);
        final cipherOK =
            AESCipher(false, hashOK, Uint8List(16), usePadding: false);
        nextObjectKey = cipherOK.processBlock(oeValue, 0, oeValue.length);
      } else {
        // "Algorithm 11: Authenticating the user password".
        final uValSalt = uValue.sublist(
            VALIDATION_SALT_OFFSET, VALIDATION_SALT_OFFSET + SALT_LENGTH);
        final hashPU = computeHash(pw, uValSalt, null);
        if (!equalsArray(hashPU, uValue, 32)) {
          throw BadPasswordException(
              KernelExceptionMessageConstant.badUserPassword);
        }
        final uKeySalt =
            uValue.sublist(KEY_SALT_OFFSET, KEY_SALT_OFFSET + SALT_LENGTH);
        final hashUK = computeHash(pw, uKeySalt, null);
        final cipherUK =
            AESCipher(false, hashUK, Uint8List(16), usePadding: false);
        nextObjectKey = cipherUK.processBlock(ueValue, 0, ueValue.length);
      }

      nextObjectKeySize = 32;
      mkey = Uint8List.fromList(nextObjectKey!);

      // "Algorithm 13: Validating the permissions". The 16-byte /Perms string
      // is decrypted with AES-256 and no padding; with a single block, CBC
      // under a zero initialisation vector is the ECB the algorithm asks for.
      if (perms.length < 16) {
        throw PdfException(
            KernelExceptionMessageConstant.standardHandlerBadDictionary);
      }
      final cipherPerms =
          AESCipher(false, nextObjectKey!, Uint8List(16), usePadding: false);
      final decPerms = cipherPerms.processBlock(perms, 0, 16);

      if (decPerms[9] != 0x61 || decPerms[10] != 0x64 || decPerms[11] != 0x62) {
        // The bytes 'a', 'd', 'b' mark a well-formed /Perms string.
        throw BadPasswordException(
            KernelExceptionMessageConstant.badUserPassword);
      }

      permissions = (decPerms[0] & 0xff) |
          ((decPerms[1] & 0xff) << 8) |
          ((decPerms[2] & 0xff) << 16) |
          ((decPerms[3] & 0xff) << 24);
      _encryptMetadata = decPerms[8] == 0x54; // 'T'
    } on BadPasswordException {
      rethrow;
    } on PdfException {
      rethrow;
    } catch (e) {
      throw PdfException(KernelExceptionMessageConstant.unknownPdfException,
          cause: e);
    }
  }

  /// "Algorithm 10: Computing the encryption dictionary's Perms (permissions)
  /// value".
  Uint8List getAes256Perms(int permissions, bool encryptMetadata) {
    final permsp = IVGenerator.getIVLen(16);
    permsp[0] = permissions & 0xFF;
    permsp[1] = (permissions >> 8) & 0xFF;
    permsp[2] = (permissions >> 16) & 0xFF;
    permsp[3] = (permissions >> 24) & 0xFF;
    permsp[4] = 0xFF;
    permsp[5] = 0xFF;
    permsp[6] = 0xFF;
    permsp[7] = 0xFF;
    permsp[8] = encryptMetadata ? 0x54 : 0x46; // 'T' or 'F'
    permsp[9] = 0x61; // 'a'
    permsp[10] = 0x64; // 'd'
    permsp[11] = 0x62; // 'b'

    final cipher =
        AESCipher(true, nextObjectKey!, Uint8List(16), usePadding: false);
    return cipher.processBlock(permsp, 0, permsp.length);
  }

  void _setAES256DicEntries(
      PdfDictionary encryptionDictionary,
      Uint8List oeKey,
      Uint8List ueKey,
      Uint8List aes256Perms,
      bool encryptMetadata,
      bool embeddedFilesOnly) {
    const int version = 5;
    final int revision = _revision6 ? 6 : 5;
    final PdfName cryptoFilter = PdfName.aesV3;

    encryptionDictionary.put(PdfName.oe, PdfString.fromBytes(oeKey, true));
    encryptionDictionary.put(PdfName.ue, PdfString.fromBytes(ueKey, true));
    encryptionDictionary.put(
        PdfName.perms, PdfString.fromBytes(aes256Perms, true));
    encryptionDictionary.put(PdfName.r, PdfNumber.fromInt(revision));
    encryptionDictionary.put(PdfName.v, PdfNumber.fromInt(version));
    encryptionDictionary.put(PdfName.length, PdfNumber.fromInt(256));

    final stdcf = PdfDictionary();
    stdcf.put(PdfName.length, PdfNumber.fromInt(32));
    if (!encryptMetadata) {
      encryptionDictionary.put(PdfName.encryptMetadata, PdfBoolean.pdfFalse);
    }
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
    stdcf.put(PdfName.cfm, cryptoFilter);
    final cf = PdfDictionary();
    cf.put(PdfName.stdCF, stdcf);
    encryptionDictionary.put(PdfName.cf, cf);
  }

  /// "Algorithm 2.A" and, for revision 6, the hardening loop of
  /// "Algorithm 2.B".
  Uint8List computeHash(
      Uint8List password, Uint8List salt, Uint8List? userKey) {
    final sha256 = DigestAlgorithms.getMessageDigest("SHA-256");
    sha256.updateAll(password);
    sha256.updateAll(salt);
    if (userKey != null) {
      sha256.updateAll(userKey);
    }
    Uint8List k = sha256.digest();

    if (_revision6) {
      final sha384 = DigestAlgorithms.getMessageDigest("SHA-384");
      final sha512 = DigestAlgorithms.getMessageDigest("SHA-512");
      final int userKeyLen = userKey?.length ?? 0;
      final int passAndUserKeyLen = password.length + userKeyLen;
      int roundNum = 0;

      while (true) {
        // a) K1 is the password, K and the user key, repeated 64 times.
        final k1Len = passAndUserKeyLen + k.length;
        final k1 = Uint8List(k1Len * 64);
        final base = Uint8List(k1Len);
        base.setRange(0, password.length, password);
        base.setRange(password.length, password.length + k.length, k);
        if (userKey != null) {
          base.setRange(password.length + k.length, k1Len, userKey);
        }
        for (int i = 0; i < 64; i++) {
          k1.setRange(i * k1Len, (i + 1) * k1Len, base);
        }

        // b) AES-128-CBC with the first 16 bytes of K as key and the next 16
        // as initialisation vector, no padding.
        final aesKey = k.sublist(0, 16);
        final aesIv = k.sublist(16, 32);
        final cipher = AESCipher(true, aesKey, aesIv, usePadding: false);
        final e = cipher.processBlock(k1, 0, k1.length);

        // c) The first 16 bytes of E, taken as a big-endian number modulo 3,
        // select SHA-256, SHA-384 or SHA-512.
        var remainder = 0;
        for (var i = 0; i < 16; i++) {
          remainder = (remainder * 256 + e[i]) % 3;
        }

        final md =
            (remainder == 0) ? sha256 : (remainder == 1 ? sha384 : sha512);

        // d) K becomes the digest of E.
        k = md.digestWithInput(e);
        roundNum++;

        // e) After 64 rounds, stop once the last byte of E is at most the
        // round number minus 32.
        if (roundNum > 63) {
          final condVal = e[e.length - 1] & 0xFF;
          if (condVal <= roundNum - 32) {
            break;
          }
        }
      }
      if (k.length != 32) {
        k = Uint8List.fromList(k.sublist(0, 32));
      }
    }
    return k;
  }

  Uint8List _truncateArray(Uint8List array) {
    if (array.length == 48) return array;
    if (array.length > 48) {
      for (int i = 48; i < array.length; i++) {
        if (array[i] != 0) {
          throw PdfException(
              KernelExceptionMessageConstant.standardHandlerBadDictionary);
        }
      }
      return Uint8List.fromList(array.sublist(0, 48));
    }
    final truncated = Uint8List(48);
    truncated.setRange(0, array.length, array);
    return truncated;
  }
}
