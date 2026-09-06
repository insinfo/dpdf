import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/aes_cipher.dart';
import 'package:dpdf/src/kernel/crypto/aes_decryptor.dart';
import 'package:dpdf/src/kernel/crypto/digest_algorithms.dart';
import 'package:dpdf/src/kernel/crypto/i_decryptor.dart';
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

/// Standard security handler using AES-256 algorithm.
class StandardHandlerUsingAes256 extends StandardSecurityHandler {
  static const int VALIDATION_SALT_OFFSET = 32;
  static const int KEY_SALT_OFFSET = 40;
  static const int SALT_LENGTH = 8;

  bool _encryptMetadata = true;
  bool _isPdf2 = false;

  StandardHandlerUsingAes256(
      PdfDictionary encryptionDictionary,
      Uint8List? userPassword,
      Uint8List? ownerPassword,
      int permissions,
      bool encryptMetadata,
      bool embeddedFilesOnly,
      PdfVersion? version) {
    _isPdf2 = version != null && version.compareTo(PdfVersion.PDF_2_0) >= 0;
    _initKeyAndFillDictionary(encryptionDictionary, userPassword, ownerPassword,
        permissions, encryptMetadata, embeddedFilesOnly);
  }

  StandardHandlerUsingAes256.read(
      PdfDictionary encryptionDictionary, Uint8List password) {
    // Intentionally left empty or private, essentially disabled.
    // Ideally we should remove it, but to keep 'read' logic we make a static method.
    throw UnimplementedError("Use fromDictionary instead");
  }

  static Future<StandardHandlerUsingAes256> fromDictionary(
      PdfDictionary encryptionDictionary, Uint8List password) async {
    final handler = StandardHandlerUsingAes256._internal();
    await handler._initKeyAndReadDictionary(encryptionDictionary, password);
    return handler;
  }

  StandardHandlerUsingAes256._internal() : super();

  bool isEncryptMetadata() => _encryptMetadata;

  @override
  void setHashKeyForNextObject(int objNumber, int objGeneration) {
    // In AES256 we don't recalculate nextObjectKey
  }

  @override
  OutputStreamEncryption getEncryptionStream(dynamic os) {
    return OutputStreamAesEncryption(os, nextObjectKey!, 0, nextObjectKeySize);
  }

  @override
  IDecryptor getDecryptor() {
    return AesDecryptor(nextObjectKey!, 0, nextObjectKeySize);
  }

  @override
  void setPermissions(int permissions, PdfDictionary encryptionDictionary) {
    super.setPermissions(permissions, encryptionDictionary);
    final aes256Perms = getAes256Perms(permissions, isEncryptMetadata());
    encryptionDictionary.put(PdfName.perms, PdfString.fromBytes(aes256Perms));
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
      Uint8List up = userPassword ?? Uint8List(0);
      if (up.length > 127) {
        up = up.sublist(0, 127);
      }
      Uint8List op = ownerPassword;
      if (op.length > 127) {
        op = op.sublist(0, 127);
      }

      final userValAndKeySalt = IVGenerator.getIVLen(16);
      final ownerValAndKeySalt = IVGenerator.getIVLen(16);
      nextObjectKey = IVGenerator.getIVLen(32);
      nextObjectKeySize = 32;

      // Algorithm 8.1
      final userValSalt = userValAndKeySalt.sublist(0, 8);
      final userKey = Uint8List(48);
      final hashUP = computeHash(up, userValSalt, null);
      userKey.setRange(0, 32, hashUP);
      userKey.setRange(32, 48, userValAndKeySalt);

      // Algorithm 8.2
      final userKeySalt = userValAndKeySalt.sublist(8, 16);
      final hashUPKey = computeHash(up, userKeySalt, null);
      final cipherUP =
          AESCipher(true, hashUPKey, Uint8List(16), usePadding: false);
      final ueKey =
          cipherUP.processBlock(nextObjectKey!, 0, nextObjectKey!.length);

      // Algorithm 9.1
      final ownerValSalt = ownerValAndKeySalt.sublist(0, 8);
      final ownerKey = Uint8List(48);
      final hashOP = computeHash(op, ownerValSalt, userKey);
      ownerKey.setRange(0, 32, hashOP);
      ownerKey.setRange(32, 48, ownerValAndKeySalt);

      // Algorithm 9.2
      final ownerKeySalt = ownerValAndKeySalt.sublist(8, 16);
      final hashOPKey = computeHash(op, ownerKeySalt, userKey);
      final cipherOP =
          AESCipher(true, hashOPKey, Uint8List(16), usePadding: false);
      final oeKey =
          cipherOP.processBlock(nextObjectKey!, 0, nextObjectKey!.length);

      // Algorithm 10
      final aes256Perms = getAes256Perms(permissions, encryptMetadata);

      this.permissions = permissions;
      this._encryptMetadata = encryptMetadata;

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
      Uint8List pw = password;
      if (pw.length > 127) {
        pw = pw.sublist(0, 127);
      }

      _isPdf2 = await _checkIsPdf2(encryptionDictionary);

      final oValue = _truncateArray(
          getIsoBytes((await encryptionDictionary.getAsString(PdfName.o))!));
      final uValue = _truncateArray(
          getIsoBytes((await encryptionDictionary.getAsString(PdfName.u))!));
      final oeValue =
          getIsoBytes((await encryptionDictionary.getAsString(PdfName.oe))!);
      final ueValue =
          getIsoBytes((await encryptionDictionary.getAsString(PdfName.ue))!);
      final perms =
          getIsoBytes((await encryptionDictionary.getAsString(PdfName.perms))!);
      final pValue = (await encryptionDictionary.getAsNumber(PdfName.p))!;
      this.permissions = pValue.intValue();

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
      final cipherPerms =
          AESCipher(false, nextObjectKey!, Uint8List(16), usePadding: false);
      final decPerms = cipherPerms.processBlock(perms, 0, perms.length);

      if (decPerms[9] != 0x61 || decPerms[10] != 0x64 || decPerms[11] != 0x62) {
        // 'adb'
        throw BadPasswordException(
            KernelExceptionMessageConstant.badUserPassword);
      }

      final permissionsDecoded = (decPerms[0] & 0xff) |
          ((decPerms[1] & 0xff) << 8) |
          ((decPerms[2] & 0xff) << 16) |
          ((decPerms[3] & 0xff) << 24);
      final encryptMetadata = decPerms[8] == 0x54; // 'T'

      this.permissions = permissionsDecoded;
      this._encryptMetadata = encryptMetadata;
    } on BadPasswordException {
      rethrow;
    } catch (e) {
      throw PdfException(KernelExceptionMessageConstant.unknownPdfException,
          cause: e);
    }
  }

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
    int version = 5;
    int revision = _isPdf2 ? 6 : 5;
    PdfName cryptoFilter = PdfName.aesV3;

    encryptionDictionary.put(PdfName.oe, PdfString.fromBytes(oeKey));
    encryptionDictionary.put(PdfName.ue, PdfString.fromBytes(ueKey));
    encryptionDictionary.put(PdfName.perms, PdfString.fromBytes(aes256Perms));
    encryptionDictionary.put(PdfName.r, PdfNumber.fromInt(revision));
    encryptionDictionary.put(PdfName.v, PdfNumber.fromInt(version));

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

  Future<bool> _checkIsPdf2(PdfDictionary encryptionDictionary) async {
    final r = await encryptionDictionary.getAsNumber(PdfName.r);
    return r != null && r.intValue() == 6;
  }

  Uint8List computeHash(
      Uint8List password, Uint8List salt, Uint8List? userKey) {
    final sha256 = DigestAlgorithms.getMessageDigest("SHA-256");
    sha256.updateAll(password);
    sha256.updateAll(salt);
    if (userKey != null) {
      sha256.updateAll(userKey);
    }
    Uint8List k = sha256.digest();

    if (_isPdf2) {
      final sha384 = DigestAlgorithms.getMessageDigest("SHA-384");
      final sha512 = DigestAlgorithms.getMessageDigest("SHA-512");
      int userKeyLen = userKey?.length ?? 0;
      int passAndUserKeyLen = password.length + userKeyLen;
      int roundNum = 0;

      while (true) {
        // a) k1 repetition length 64 times
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

        // b) AES-128-CBC encryption with key from first 16 bytes of k and IV from next 16 bytes.
        final aesKey = k.sublist(0, 16);
        final aesIv = k.sublist(16, 32);
        final cipher = AESCipher(true, aesKey, aesIv, usePadding: false);
        final e = cipher.processBlock(k1, 0, k1.length);

        // c) Choose SHA based on remainder of e[0..15] % 3
        final bigE = BigInt.parse(
            e
                .sublist(0, 16)
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(),
            radix: 16);
        final remainder = (bigE % BigInt.from(3)).toInt();

        final md =
            (remainder == 0) ? sha256 : (remainder == 1 ? sha384 : sha512);

        // d) k = hash(e)
        k = md.digestWithInput(e);
        roundNum++;

        // e) Termination condition
        if (roundNum > 63) {
          int condVal = e[e.length - 1] & 0xFF;
          if (condVal <= roundNum - 32) {
            break;
          }
        }
      }
      if (k.length != 32) {
        k = k.sublist(0, 32);
      }
    }
    return k;
  }

  Uint8List _truncateArray(Uint8List array) {
    if (array.length == 48) return array;
    if (array.length > 48) {
      for (int i = 48; i < array.length; i++) {
        if (array[i] != 0) {
          throw PdfException(KernelExceptionMessageConstant
              .alreadyClosed); // Using alreadyClosed as generic error for now
        }
      }
      return array.sublist(0, 48);
    }
    final truncated = Uint8List(48);
    truncated.setRange(0, array.length, array);
    return truncated;
  }
}
