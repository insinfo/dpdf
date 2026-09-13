import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/crypt_filter.dart';
import 'package:dpdf/src/kernel/pdf/encryption_constants.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_encryption.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_version.dart';
import 'package:dpdf/src/kernel/pdf/reader_properties.dart';
import 'package:dpdf/src/kernel/pdf/writer_properties.dart';
import 'package:test/test.dart';

Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

final Uint8List documentId =
    Uint8List.fromList(List<int>.generate(16, (i) => (i * 11 + 1) & 0xFF));

final Map<String, int> algorithms = {
  'RC4 40': EncryptionConstants.standardEncryption40,
  'RC4 128': EncryptionConstants.standardEncryption128,
  'AES 128': EncryptionConstants.encryptionAes128,
  'AES 256': EncryptionConstants.encryptionAes256,
};

PdfEncryption writer(int algorithm, {PdfVersion? version}) =>
    PdfEncryption.standard(
      userPassword: bytes('open-me'),
      ownerPassword: bytes('own-me'),
      permissions: EncryptionConstants.allowPrinting,
      encryptionAlgorithm: algorithm,
      documentId: documentId,
      version: version,
    );

void main() {
  group('Stream and string round trips', () {
    final payload = bytes('Stream data shall be encrypted after applying all '
        'stream encoding filters, per 7.6.2.');

    for (final entry in algorithms.entries) {
      test('${entry.key} decrypts what it encrypted', () async {
        final encryption = writer(entry.value);
        final encrypted = encryption.encryptStream(payload, 17, 0);
        expect(encrypted, isNot(payload));

        final reader = await PdfEncryption.createFromDictionary(
            encryption.pdfRepresentation(), bytes('open-me'), documentId);
        expect(reader.decryptStream(encrypted, 17, 0), payload);
      });

      if (entry.value != EncryptionConstants.encryptionAes256) {
        test('${entry.key} binds the ciphertext to the object identifier',
            () async {
          // "Algorithm 1", steps (b) to (d), mix the object and generation
          // numbers into the key, so another object cannot read the data.
          final encryption = writer(entry.value);
          final encrypted = encryption.encryptStream(payload, 17, 0);
          Uint8List? wrongObject;
          try {
            wrongObject = encryption.decryptStream(encrypted, 18, 0);
          } catch (_) {
            wrongObject = null;
          }
          expect(wrongObject, isNot(payload));
        });
      }

      test('${entry.key} encrypts strings with the /StrF filter', () async {
        final encryption = writer(entry.value);
        encryption.setHashKeyForNextObject(4, 0);
        final encrypted = encryption.encryptString(bytes('a title'));
        expect(encrypted, isNot(bytes('a title')));
        final reader = await PdfEncryption.createFromDictionary(
            encryption.pdfRepresentation(), bytes('own-me'), documentId);
        reader.setHashKeyForNextObject(4, 0);
        expect(reader.decryptString(encrypted), bytes('a title'));
      });
    }

    test('AESV3 uses the file key as is, so the object number is irrelevant',
        () {
      // ISO 32000-2 drops the per-object derivation for AESV3.
      final encryption = writer(EncryptionConstants.encryptionAes256);
      final encrypted = encryption.encryptStream(payload, 17, 0);
      expect(encryption.decryptStream(encrypted, 18, 4), payload);
    });

    test('AES-256 revision 6 round trips a stream', () async {
      final encryption = writer(EncryptionConstants.encryptionAes256,
          version: PdfVersion.PDF_2_0);
      final encrypted = encryption.encryptStream(payload, 2, 0);
      final reader = await PdfEncryption.createFromDictionary(
          encryption.pdfRepresentation(), bytes('open-me'), documentId);
      expect(reader.decryptStream(encrypted, 2, 0), payload);
    });

    test('the legacy stream API round trips through encryptByteArray',
        () async {
      final encryption = writer(EncryptionConstants.encryptionAes128);
      encryption.setHashKeyForNextObject(11, 0);
      final encrypted = encryption.encryptByteArray(payload);
      final reader = await PdfEncryption.createFromDictionary(
          encryption.pdfRepresentation(), bytes('open-me'), documentId);
      reader.setHashKeyForNextObject(11, 0);
      expect(reader.decryptByteArray(encrypted), payload);
    });
  });

  group('Object streams and the encryption dictionary', () {
    test('strings inside an object stream are not separately encrypted', () {
      // 7.5.7: "In an encrypted file ... strings occurring anywhere in an
      // object stream shall not be separately encrypted."
      final encryption = writer(EncryptionConstants.encryptionAes128);
      encryption.setHashKeyForNextObject(21, 0);
      final plain = bytes('inside an object stream');
      expect(encryption.isInObjectStream(), isFalse);
      encryption.setInObjectStream(true);
      expect(encryption.encryptString(plain), plain);
      expect(encryption.decryptString(plain), plain);
      encryption.setInObjectStream(false);
      expect(encryption.encryptString(plain), isNot(plain));
    });

    test('the object stream itself is still encrypted as a stream', () async {
      final encryption = writer(EncryptionConstants.encryptionAes128);
      final objStmPayload = bytes('1 0 2 34 << /Title (kept in clear) >>');
      final encrypted = encryption.encryptStream(objStmPayload, 21, 0);
      expect(encrypted, isNot(objStmPayload));
      final reader = await PdfEncryption.createFromDictionary(
          encryption.pdfRepresentation(), bytes('open-me'), documentId);
      expect(reader.decryptStream(encrypted, 21, 0), objStmPayload);
    });

    test('the encryption dictionary is recognised so it stays in clear', () {
      // 7.6.1: "The contents of the encryption dictionary shall not be
      // encrypted".
      final encryption = writer(EncryptionConstants.encryptionAes128);
      expect(encryption.isEncryptionDictionary(encryption.pdfRepresentation()),
          isTrue);
      expect(encryption.isEncryptionDictionary(PdfDictionary()), isFalse);
    });
  });

  group('Crypt filter selection', () {
    test('a Crypt filter decode parameters /Name overrides the default',
        () async {
      final encryption = writer(EncryptionConstants.encryptionAes128);
      final metadata = bytes('<?xpacket begin=...?>');
      final asIdentity = encryption.encryptStream(metadata, 6, 0,
          cryptFilterName: PdfName.identity);
      expect(asIdentity, metadata);
      final asStdCF = encryption.encryptStream(metadata, 6, 0,
          cryptFilterName: PdfName.stdCF);
      expect(asStdCF, isNot(metadata));
      expect(
          encryption.decryptStream(asStdCF, 6, 0,
              cryptFilterName: PdfName.stdCF),
          metadata);
    });

    test('an unknown crypt filter name falls back to Identity', () {
      final encryption = writer(EncryptionConstants.encryptionAes128);
      final data = bytes('unchanged');
      expect(
          encryption.encryptStream(data, 6, 0,
              cryptFilterName: PdfName.intern('NoSuchFilter')),
          data);
    });

    test('metadata stays in clear when /EncryptMetadata is false', () {
      final encryption = writer(EncryptionConstants.encryptionAes128 |
          EncryptionConstants.doNotEncryptMetadata);
      final metadata = bytes('plaintext metadata');
      expect(
          encryption.encryptStream(metadata, 6, 0, isMetadata: true), metadata);
      expect(encryption.encryptStream(metadata, 6, 0), isNot(metadata));
    });

    test('embedded files use the /EFF filter', () async {
      final encryption = writer(EncryptionConstants.encryptionAes128 |
          EncryptionConstants.embeddedFilesOnly);
      final attachment = bytes('attached bytes');
      expect(encryption.encryptStream(attachment, 8, 0), attachment);
      final encrypted =
          encryption.encryptStream(attachment, 8, 0, isEmbeddedFile: true);
      expect(encrypted, isNot(attachment));
      expect(encryption.decryptStream(encrypted, 8, 0, isEmbeddedFile: true),
          attachment);
    });

    test('streamFilterFor reports the filter that applies', () {
      final encryption = writer(EncryptionConstants.encryptionAes256);
      expect(encryption.streamFilterFor().method, CryptFilterMethod.aesV3);
      expect(
          encryption
              .streamFilterFor(cryptFilterName: PdfName.identity)
              .isIdentity,
          isTrue);
    });
  });

  group('Malformed encryption dictionaries', () {
    test('a non-standard /Filter is refused by the standard reader', () {
      final dictionary = PdfDictionary();
      dictionary.put(PdfName.filter, PdfName.intern('Adobe.PubSec'));
      dictionary.put(PdfName.v, PdfNumber.fromInt(1));
      expect(
          PdfEncryption.createFromDictionary(
              dictionary, Uint8List(0), documentId),
          throwsA(isA<Object>()));
    });

    test('a missing /O entry is reported', () {
      final dictionary = PdfDictionary();
      dictionary.put(PdfName.filter, PdfName.standard);
      dictionary.put(PdfName.v, PdfNumber.fromInt(1));
      dictionary.put(PdfName.r, PdfNumber.fromInt(2));
      dictionary.put(PdfName.p, PdfNumber.fromInt(-1));
      dictionary.put(PdfName.u, PdfString.fromBytes(Uint8List(32), true));
      expect(
          PdfEncryption.createFromDictionary(
              dictionary, Uint8List(0), documentId),
          throwsA(isA<Object>()));
    });

    test('an unsupported revision is reported', () {
      final dictionary = PdfDictionary();
      dictionary.put(PdfName.filter, PdfName.standard);
      dictionary.put(PdfName.v, PdfNumber.fromInt(3));
      dictionary.put(PdfName.r, PdfNumber.fromInt(1));
      dictionary.put(PdfName.length, PdfNumber.fromInt(128));
      expect(
          PdfEncryption.createFromDictionary(
              dictionary, Uint8List(0), documentId),
          throwsA(isA<Object>()));
    });
  });

  group('Properties', () {
    test('ReaderProperties carries the public-key credentials', () {
      final properties = ReaderProperties()..setPassword(bytes('abc'));
      expect(properties.password, bytes('abc'));
      expect(properties.certificate, isNull);
      final copy = ReaderProperties.from(properties);
      expect(copy.password, bytes('abc'));
      expect(copy.certificateKey, isNull);
    });

    test('setPassword clears any certificate credentials', () {
      final properties = ReaderProperties();
      properties.certificate = null;
      properties.setPassword(bytes('abc'));
      expect(properties.certificate, isNull);
      expect(properties.certificateKey, isNull);
    });

    test('WriterProperties switches between the two encryption kinds', () {
      final properties = WriterProperties()
        ..setStandardEncryption(
            bytes('u'),
            bytes('o'),
            EncryptionConstants.allowPrinting,
            EncryptionConstants.encryptionAes256);
      expect(properties.isStandardEncryptionUsed, isTrue);
      expect(properties.isPublicKeyEncryptionUsed, isFalse);
      expect(
          properties.encryptionAlgorithm, EncryptionConstants.encryptionAes256);

      properties
          .setPublicKeyEncryption([], EncryptionConstants.encryptionAes128);
      expect(properties.isPublicKeyEncryptionUsed, isTrue);
      expect(properties.isStandardEncryptionUsed, isFalse);
      expect(properties.userPassword, isNull);
    });
  });
}
