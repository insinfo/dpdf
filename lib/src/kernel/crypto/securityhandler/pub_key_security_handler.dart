import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/cms_enveloped_data.dart';
import 'package:dpdf/src/kernel/crypto/crypt_filter.dart';
import 'package:dpdf/src/kernel/crypto/crypt_filter_cipher.dart';
import 'package:dpdf/src/kernel/crypto/aes_decryptor.dart';
import 'package:dpdf/src/kernel/crypto/decryptor.dart';
import 'package:dpdf/src/kernel/crypto/digest_algorithms.dart';
import 'package:dpdf/src/kernel/crypto/iv_generator.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_aes_encryption.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_encryption.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_standard_encryption.dart';
import 'package:dpdf/src/kernel/crypto/standard_decryptor.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/security_handler.dart';
import 'package:dpdf/src/kernel/exceptions/kernel_exception_message_constant.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/encryption_constants.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/pki/rsa.dart';
import 'package:dpdf/src/sign/x509_certificate.dart';

/// A set of recipients that share one set of access permissions.
///
/// ISO 32000-1:2008, Table 23: "There shall be only one PKCS#7 object per
/// unique set of access permissions; if a recipient appears in more than one
/// list, the permissions used shall be those in the first matching list."
class PublicKeyRecipientGroup {
  /// The certificates whose holders may open the document.
  final List<X509Certificate> certificates;

  /// The permission flags of Table 24 granted to this group.
  final int permissions;

  PublicKeyRecipientGroup(this.certificates, this.permissions);
}

/// The security handler of ISO 32000-1:2008, 7.6.4 "Public-Key Security
/// Handlers".
///
/// The handler stores one PKCS#7 enveloped data object per recipient group.
/// Each envelope contains a 20-byte seed and, for document-level encryption,
/// four permission bytes; the file encryption key is the digest of the seed
/// followed by every recipient object, as prescribed by 7.6.4.3.
class PubKeySecurityHandler extends SecurityHandler {
  /// Bit 2 of Table 24: "When set permits change of encryption and enables all
  /// other permissions."
  static const int allowAll = 2;

  /// The binary-encoded PKCS#7 objects of the `/Recipients` entry, in the
  /// order in which they appear in the array.
  final List<Uint8List> recipients = [];

  /// The encryption algorithm selector of [EncryptionConstants].
  int encryptionAlgorithm;

  /// Whether the document-level metadata stream is encrypted.
  bool encryptMetadata;

  /// Whether only embedded files are encrypted.
  bool embeddedFilesOnly;

  /// The permissions recovered from, or written into, the envelope.
  int permissions = allowAll;

  /// The crypt filter that protects streams and strings.
  late CryptFilter defaultFilter;

  PubKeySecurityHandler._(
      {required this.encryptionAlgorithm,
      required this.encryptMetadata,
      required this.embeddedFilesOnly});

  /// The key length, in bits, implied by [encryptionAlgorithm].
  static int keyLengthBitsOf(int encryptionAlgorithm) {
    switch (encryptionAlgorithm & EncryptionConstants.encryptionMask) {
      case EncryptionConstants.standardEncryption40:
        return 40;
      case EncryptionConstants.encryptionAes256:
        return 256;
      default:
        return 128;
    }
  }

  /// The crypt filter method implied by [encryptionAlgorithm].
  static CryptFilterMethod methodOf(int encryptionAlgorithm) {
    switch (encryptionAlgorithm & EncryptionConstants.encryptionMask) {
      case EncryptionConstants.standardEncryption40:
      case EncryptionConstants.standardEncryption128:
        return CryptFilterMethod.v2;
      case EncryptionConstants.encryptionAes256:
        return CryptFilterMethod.aesV3;
      default:
        return CryptFilterMethod.aesV2;
    }
  }

  /// The `/SubFilter` value of 7.6.4.2 implied by [encryptionAlgorithm].
  ///
  /// `adbe.pkcs7.s3` and `adbe.pkcs7.s4` "shall be used when not using crypt
  /// filters", `adbe.pkcs7.s5` "shall be used when using crypt filters".
  static PdfName subFilterOf(int encryptionAlgorithm) {
    switch (encryptionAlgorithm & EncryptionConstants.encryptionMask) {
      case EncryptionConstants.standardEncryption40:
        return EncryptionNames.adbePkcs7s3;
      case EncryptionConstants.standardEncryption128:
        return EncryptionNames.adbePkcs7s4;
      default:
        return EncryptionNames.adbePkcs7s5;
    }
  }

  /// Creates a handler and fills [encryptionDictionary] for writing.
  factory PubKeySecurityHandler.create({
    required PdfDictionary encryptionDictionary,
    required List<PublicKeyRecipientGroup> groups,
    required int encryptionAlgorithm,
    bool encryptMetadata = true,
    bool embeddedFilesOnly = false,
    Uint8List? seed,
    CmsContentEncryption contentEncryption = CmsContentEncryption.aes128Cbc,
  }) {
    if (groups.isEmpty) {
      throw PdfException(
          KernelExceptionMessageConstant.noCompatibleEncryptionFound);
    }
    final handler = PubKeySecurityHandler._(
        encryptionAlgorithm: encryptionAlgorithm,
        encryptMetadata: encryptMetadata,
        embeddedFilesOnly: embeddedFilesOnly);
    // 7.6.4.3: "A 20-byte seed that shall be used to create the encryption
    // key ... a unique random number generated by the security handler".
    final documentSeed = seed ?? IVGenerator.getIVLen(20);
    if (documentSeed.length != 20) {
      throw ArgumentError('The public-key seed must be 20 bytes long');
    }
    for (final group in groups) {
      final payload = Uint8List(24);
      payload.setRange(0, 20, documentSeed);
      // "A 4-byte value defining the permissions, least significant byte
      // first."
      payload[20] = group.permissions & 0xFF;
      payload[21] = (group.permissions >> 8) & 0xFF;
      payload[22] = (group.permissions >> 16) & 0xFF;
      payload[23] = (group.permissions >> 24) & 0xFF;
      handler.recipients.add(CmsEnvelopedData.encode(
          certificates: group.certificates,
          content: payload,
          algorithm: contentEncryption));
    }
    handler.permissions = groups.first.permissions;
    handler.mkey = handler._computeKey(documentSeed);
    handler._buildDictionary(encryptionDictionary);
    return handler;
  }

  /// Reads an existing public-key encryption dictionary.
  ///
  /// Returns a handler whose [mkey] is the file encryption key, or throws when
  /// [certificate] is not among the recipients.
  static Future<PubKeySecurityHandler> read(
      PdfDictionary encryptionDictionary,
      X509Certificate certificate,
      RSAPrivateKey privateKey) async {
    final version =
        (await encryptionDictionary.numberEntry(PdfName.v))?.intValue() ?? 1;
    final lengthBits =
        (await encryptionDictionary.numberEntry(PdfName.length))?.intValue() ??
            40;
    var encryptMetadata =
        (await encryptionDictionary.booleanEntry(PdfName.encryptMetadata))
                ?.getValue() ??
            true;

    final recipients = <Uint8List>[];
    CryptFilter? filter;
    var embeddedFilesOnly = false;

    if (version >= 4) {
      final configuration =
          await CryptFilterConfiguration.fromEncryptionDictionary(
              encryptionDictionary);
      filter = configuration.streamFilter.isIdentity
          ? configuration.embeddedFileFilter
          : configuration.streamFilter;
      embeddedFilesOnly = configuration.streamFilter.isIdentity &&
          !configuration.embeddedFileFilter.isIdentity;
      recipients.addAll(filter.recipients);
      encryptMetadata = filter.encryptMetadata && encryptMetadata;
    } else {
      final array =
          await encryptionDictionary.get(EncryptionNames.recipients, true);
      if (array is PdfArray) {
        for (var i = 0; i < array.size(); i++) {
          final entry = await array.get(i);
          if (entry is PdfString) {
            recipients.add(entry.getValueBytes() ?? Uint8List(0));
          }
        }
      } else if (array is PdfString) {
        recipients.add(array.getValueBytes() ?? Uint8List(0));
      }
    }
    if (recipients.isEmpty) {
      throw PdfException(
          KernelExceptionMessageConstant.standardHandlerBadDictionary);
    }

    final algorithm = _algorithmFor(version, lengthBits, filter?.method);
    final handler = PubKeySecurityHandler._(
        encryptionAlgorithm: algorithm,
        encryptMetadata: encryptMetadata,
        embeddedFilesOnly: embeddedFilesOnly);
    handler.recipients.addAll(recipients);
    handler.defaultFilter = filter ??
        CryptFilter(
            name: EncryptionNames.defaultCryptFilter,
            method: methodOf(algorithm),
            length: lengthBits);

    Uint8List? envelope;
    for (final recipient in recipients) {
      final decoded = CmsEnvelopedData.decode(recipient);
      final content = decoded.unwrap(certificate, privateKey);
      if (content != null) {
        envelope = content;
        break;
      }
    }
    if (envelope == null || envelope.length < 20) {
      throw PdfException(
          KernelExceptionMessageConstant.noCompatibleEncryptionFound);
    }
    if (envelope.length >= 24) {
      handler.permissions = (envelope[20] & 0xFF) |
          ((envelope[21] & 0xFF) << 8) |
          ((envelope[22] & 0xFF) << 16) |
          ((envelope[23] & 0xFF) << 24);
    }
    handler.mkey = handler._computeKey(
        Uint8List.fromList(envelope.sublist(0, 20)));
    return handler;
  }

  static int _algorithmFor(
      int version, int lengthBits, CryptFilterMethod? method) {
    if (method == CryptFilterMethod.aesV3 || version == 5) {
      return EncryptionConstants.encryptionAes256;
    }
    if (method == CryptFilterMethod.aesV2) {
      return EncryptionConstants.encryptionAes128;
    }
    if (version == 1 && lengthBits <= 40) {
      return EncryptionConstants.standardEncryption40;
    }
    return EncryptionConstants.standardEncryption128;
  }

  /// "Algorithm: computing the public-key file encryption key" of 7.6.4.3.
  ///
  /// The digest covers the 20 bytes of seed, then the bytes of each item of
  /// the `Recipients` array in order, and finally four bytes with the value
  /// 0xFF when the document metadata is left as plaintext. The first n/8 bytes
  /// of the digest become the encryption key.
  Uint8List _computeKey(Uint8List seed) {
    final bits = keyLengthBitsOf(encryptionAlgorithm);
    // ISO 32000-1 specifies SHA-1; the 256-bit AES extension of ISO 32000-2
    // uses SHA-256, whose output is exactly the required key length.
    final digest = DigestAlgorithms.getMessageDigest(bits > 128 ? 'SHA-256' : 'SHA-1');
    digest.updateAll(seed);
    for (final recipient in recipients) {
      digest.updateAll(recipient);
    }
    if (!encryptMetadata) {
      digest.updateAll(Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]));
    }
    final output = digest.digest();
    final size = bits ~/ 8;
    return Uint8List.fromList(output.sublist(0, size));
  }

  void _buildDictionary(PdfDictionary encryptionDictionary) {
    final mode = encryptionAlgorithm & EncryptionConstants.encryptionMask;
    final bits = keyLengthBitsOf(encryptionAlgorithm);
    encryptionDictionary.put(PdfName.filter, EncryptionNames.adobePubSec);
    encryptionDictionary.put(
        PdfName.subFilter, subFilterOf(encryptionAlgorithm));
    encryptionDictionary.put(PdfName.p, PdfNumber.fromInt(permissions));

    final recipientArray = PdfArray();
    for (final recipient in recipients) {
      recipientArray.add(PdfString.fromBytes(recipient, true));
    }

    if (mode == EncryptionConstants.standardEncryption40) {
      encryptionDictionary.put(PdfName.v, PdfNumber.fromInt(1));
      encryptionDictionary.put(PdfName.r, PdfNumber.fromInt(2));
      encryptionDictionary.put(EncryptionNames.recipients, recipientArray);
      defaultFilter = CryptFilter(
          name: EncryptionNames.defaultCryptFilter,
          method: CryptFilterMethod.v2,
          length: bits);
      return;
    }
    if (mode == EncryptionConstants.standardEncryption128) {
      encryptionDictionary.put(PdfName.v, PdfNumber.fromInt(2));
      encryptionDictionary.put(PdfName.r, PdfNumber.fromInt(3));
      encryptionDictionary.put(PdfName.length, PdfNumber.fromInt(bits));
      encryptionDictionary.put(EncryptionNames.recipients, recipientArray);
      defaultFilter = CryptFilter(
          name: EncryptionNames.defaultCryptFilter,
          method: CryptFilterMethod.v2,
          length: bits);
      return;
    }

    // adbe.pkcs7.s5: the recipient list lives in the crypt filter dictionary,
    // Table 27.
    final isAes256 = mode == EncryptionConstants.encryptionAes256;
    final filterName = embeddedFilesOnly
        ? EncryptionNames.defEmbeddedFile
        : EncryptionNames.defaultCryptFilter;
    defaultFilter = CryptFilter(
      name: filterName,
      method: isAes256 ? CryptFilterMethod.aesV3 : CryptFilterMethod.aesV2,
      length: bits,
      authEvent: embeddedFilesOnly ? PdfName.efOpen : PdfName.docOpen,
      encryptMetadata: encryptMetadata,
      recipients: recipients,
    );

    encryptionDictionary.put(PdfName.v, PdfNumber.fromInt(isAes256 ? 5 : 4));
    encryptionDictionary.put(PdfName.r, PdfNumber.fromInt(isAes256 ? 6 : 4));
    encryptionDictionary.put(PdfName.length, PdfNumber.fromInt(bits));
    if (!encryptMetadata) {
      encryptionDictionary.put(PdfName.encryptMetadata, PdfBoolean.pdfFalse);
    }
    final cf = PdfDictionary();
    cf.put(filterName, defaultFilter.toDictionary());
    encryptionDictionary.put(PdfName.cf, cf);
    if (embeddedFilesOnly) {
      encryptionDictionary.put(PdfName.eff, filterName);
      encryptionDictionary.put(PdfName.strF, PdfName.identity);
      encryptionDictionary.put(PdfName.stmF, PdfName.identity);
    } else {
      encryptionDictionary.put(PdfName.strF, filterName);
      encryptionDictionary.put(PdfName.stmF, filterName);
    }
  }

  CryptFilterCipher _cipher() => CryptFilterCipher(defaultFilter, mkey);

  @override
  void setHashKeyForNextObject(int objNumber, int objGeneration) {
    final cipher = _cipher();
    nextObjectKey = cipher.objectKey(objNumber, objGeneration);
    nextObjectKeySize = nextObjectKey!.length;
  }

  @override
  OutputStreamEncryption getEncryptionStream(dynamic os) {
    final key = nextObjectKey ?? mkey;
    if (defaultFilter.method == CryptFilterMethod.v2) {
      return OutputStreamStandardEncryption(os, key, 0, key.length);
    }
    return OutputStreamAesEncryption(os, key, 0, key.length);
  }

  @override
  Decryptor getDecryptor() {
    final key = nextObjectKey ?? mkey;
    if (defaultFilter.method == CryptFilterMethod.v2) {
      return StandardDecryptor(key, 0, key.length);
    }
    return AesDecryptor(key, 0, key.length);
  }
}
