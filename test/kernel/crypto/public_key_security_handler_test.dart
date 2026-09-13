import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/commons/digest/digest_bytes.dart';
import 'package:dpdf/src/kernel/crypto/cms_enveloped_data.dart';
import 'package:dpdf/src/kernel/crypto/crypt_filter.dart';
import 'package:dpdf/src/kernel/crypto/rsa_key_transport.dart';
import 'package:dpdf/src/kernel/crypto/securityhandler/pub_key_security_handler.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/encryption_constants.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_encryption.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/pki/pki_utils.dart';
import 'package:dpdf/src/sign/x509_certificate.dart';
import 'package:pointycastle/export.dart' as oracle;
import 'package:test/test.dart';

Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

class Holder {
  final X509Certificate certificate;
  final RSAPrivateKey privateKey;
  final RSAPublicKey publicKey;
  Holder(this.certificate, this.privateKey, this.publicKey);

  static Holder create(String name, int serial) {
    final pair = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;
    final certificate = X509Certificate(PkiUtils.createCertificate(
        subjectDN: 'CN=$name',
        issuerDN: 'CN=$name',
        issuerPrivateKey: privateKey,
        subjectPublicKey: publicKey,
        serialNumber: BigInt.from(serial),
        notBefore: DateTime.utc(2020),
        notAfter: DateTime.utc(2040)));
    return Holder(certificate, privateKey, publicKey);
  }
}

void main() {
  late Holder alice;
  late Holder bob;
  late Holder mallory;

  setUpAll(() {
    alice = Holder.create('Alice', 101);
    bob = Holder.create('Bob', 102);
    mallory = Holder.create('Mallory', 103);
  });

  group('RSAES-PKCS1-v1_5 key transport', () {
    test('round trips a content encryption key', () {
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i * 3));
      final wrapped = RsaKeyTransport.encrypt(alice.publicKey, key);
      expect(wrapped.length, (alice.publicKey.modulus.bitLength + 7) ~/ 8);
      expect(RsaKeyTransport.decrypt(alice.privateKey, wrapped), key);
    });

    test('an independent oracle decrypts what the library produced', () {
      final key = bytes('0123456789abcdef');
      final wrapped = RsaKeyTransport.encrypt(alice.publicKey, key);
      final pcPrivate = oracle.RSAPrivateKey(alice.privateKey.modulus,
          alice.privateKey.exponent, alice.privateKey.p, alice.privateKey.q);
      final engine = oracle.PKCS1Encoding(oracle.RSAEngine())
        ..init(false,
            oracle.PrivateKeyParameter<oracle.RSAPrivateKey>(pcPrivate));
      expect(engine.process(wrapped), key);
    });

    test('the library decrypts what an independent oracle produced', () {
      final key = bytes('fedcba9876543210');
      final pcPublic =
          oracle.RSAPublicKey(alice.publicKey.modulus, alice.publicKey.exponent);
      final engine = oracle.PKCS1Encoding(oracle.RSAEngine())
        ..init(
            true, oracle.PublicKeyParameter<oracle.RSAPublicKey>(pcPublic));
      final wrapped = engine.process(key);
      expect(RsaKeyTransport.decrypt(alice.privateKey, wrapped), key);
    });

    test('a tampered block is rejected', () {
      final key = bytes('0123456789abcdef');
      final wrapped = RsaKeyTransport.encrypt(alice.publicKey, key);
      final tampered = Uint8List.fromList(wrapped)..[5] ^= 0x55;
      expect(() => RsaKeyTransport.decrypt(alice.privateKey, tampered),
          throwsA(anyOf(isA<FormatException>(), isA<ArgumentError>())));
    });

    test('a message larger than the modulus is refused', () {
      expect(() => RsaKeyTransport.encrypt(alice.publicKey, Uint8List(200)),
          throwsArgumentError);
    });
  });

  group('CMS enveloped data', () {
    test('every recipient recovers the same payload', () {
      final payload = bytes('20-byte seed plus perm');
      final encoded = CmsEnvelopedData.encode(
          certificates: [alice.certificate, bob.certificate],
          content: payload);
      final decoded = CmsEnvelopedData.decode(encoded);
      expect(decoded.recipients.length, 2);
      expect(decoded.contentEncryption, CmsContentEncryption.aes128Cbc);
      expect(decoded.initializationVector.length, 16);
      expect(decoded.unwrap(alice.certificate, alice.privateKey), payload);
      expect(decoded.unwrap(bob.certificate, bob.privateKey), payload);
    });

    test('a certificate outside the list recovers nothing', () {
      final encoded = CmsEnvelopedData.encode(
          certificates: [alice.certificate], content: bytes('payload'));
      final decoded = CmsEnvelopedData.decode(encoded);
      expect(decoded.unwrap(mallory.certificate, mallory.privateKey), isNull);
    });

    test('AES-256 content encryption round trips', () {
      final payload = bytes('a longer payload for the 256-bit variant');
      final encoded = CmsEnvelopedData.encode(
          certificates: [alice.certificate],
          content: payload,
          algorithm: CmsContentEncryption.aes256Cbc);
      final decoded = CmsEnvelopedData.decode(encoded);
      expect(decoded.contentEncryption, CmsContentEncryption.aes256Cbc);
      expect(decoded.unwrap(alice.certificate, alice.privateKey), payload);
    });

    test('a signed data object is refused', () {
      final encoded = CmsEnvelopedData.encode(
          certificates: [alice.certificate], content: bytes('x'));
      final broken = Uint8List.fromList(encoded);
      // Flip the last arc of the content type OID, 1.2.840.113549.1.7.3.
      final index = broken.indexOf(0x07);
      broken[index + 1] = 0x02;
      expect(() => CmsEnvelopedData.decode(broken), throwsFormatException);
    });

    test('Triple DES enveloped data is read-only', () {
      expect(
          () => CmsEnvelopedData.encode(
              certificates: [alice.certificate],
              content: bytes('x'),
              algorithm: CmsContentEncryption.desEde3Cbc),
          throwsA(isA<UnsupportedError>()));
    });
  });

  group('Public-key encryption dictionary', () {
    test('adbe.pkcs7.s3 is written for RC4 40', () async {
      final encryption = PdfEncryption.publicKey(
          recipients: [
            PublicKeyRecipientGroup([alice.certificate], 0xFFFFFFFC)
          ],
          encryptionAlgorithm: EncryptionConstants.standardEncryption40);
      final dictionary = encryption.pdfRepresentation();
      expect((await dictionary.nameEntry(PdfName.filter))!.getValue(),
          'Adobe.PubSec');
      expect((await dictionary.nameEntry(PdfName.subFilter))!.getValue(),
          'adbe.pkcs7.s3');
      expect((await dictionary.numberEntry(PdfName.v))!.intValue(), 1);
      expect((await dictionary.numberEntry(PdfName.r))!.intValue(), 2);
      final recipients =
          await dictionary.get(EncryptionNames.recipients, true) as PdfArray;
      expect(recipients.size(), 1);
      expect(encryption.getFileEncryptionKey().length, 5);
    });

    test('adbe.pkcs7.s4 is written for RC4 128', () async {
      final encryption = PdfEncryption.publicKey(
          recipients: [
            PublicKeyRecipientGroup([alice.certificate], 0xFFFFFFFC)
          ],
          encryptionAlgorithm: EncryptionConstants.standardEncryption128);
      final dictionary = encryption.pdfRepresentation();
      expect((await dictionary.nameEntry(PdfName.subFilter))!.getValue(),
          'adbe.pkcs7.s4');
      expect((await dictionary.numberEntry(PdfName.v))!.intValue(), 2);
      expect((await dictionary.numberEntry(PdfName.length))!.intValue(), 128);
      expect(encryption.getFileEncryptionKey().length, 16);
    });

    test('adbe.pkcs7.s5 puts the recipients inside the crypt filter',
        () async {
      final encryption = PdfEncryption.publicKey(
          recipients: [
            PublicKeyRecipientGroup([alice.certificate], 0xFFFFFFFC)
          ],
          encryptionAlgorithm: EncryptionConstants.encryptionAes128);
      final dictionary = encryption.pdfRepresentation();
      expect((await dictionary.nameEntry(PdfName.subFilter))!.getValue(),
          'adbe.pkcs7.s5');
      expect((await dictionary.numberEntry(PdfName.v))!.intValue(), 4);
      expect((await dictionary.nameEntry(PdfName.stmF))!.getValue(),
          'DefaultCryptFilter');
      final cf = await dictionary.dictionaryEntry(PdfName.cf);
      final filter =
          await cf!.dictionaryEntry(EncryptionNames.defaultCryptFilter);
      expect((await filter!.nameEntry(PdfName.cfm))!.getValue(), 'AESV2');
      final recipients =
          await filter.get(EncryptionNames.recipients, true) as PdfArray;
      expect(recipients.size(), 1);
      expect((await recipients.get(0)) is PdfString, isTrue);
    });

    test('AES-256 public-key encryption writes /V 5 and AESV3', () async {
      final encryption = PdfEncryption.publicKey(
          recipients: [
            PublicKeyRecipientGroup([alice.certificate], 0xFFFFFFFC)
          ],
          encryptionAlgorithm: EncryptionConstants.encryptionAes256);
      final dictionary = encryption.pdfRepresentation();
      expect((await dictionary.numberEntry(PdfName.v))!.intValue(), 5);
      expect((await dictionary.numberEntry(PdfName.r))!.intValue(), 6);
      expect((await dictionary.numberEntry(PdfName.length))!.intValue(), 256);
      expect(encryption.getFileEncryptionKey().length, 32);
    });
  });

  group('Public-key authentication', () {
    for (final entry in {
      'RC4 40': EncryptionConstants.standardEncryption40,
      'RC4 128': EncryptionConstants.standardEncryption128,
      'AES 128': EncryptionConstants.encryptionAes128,
      'AES 256': EncryptionConstants.encryptionAes256,
    }.entries) {
      test('${entry.key} recovers the file key for a listed recipient',
          () async {
        final written = PdfEncryption.publicKey(
            recipients: [
              PublicKeyRecipientGroup(
                  [alice.certificate, bob.certificate], 0xFFFFFFFC)
            ],
            encryptionAlgorithm: entry.value);
        for (final holder in [alice, bob]) {
          final read = await PdfEncryption.createFromDictionaryWithCertificate(
              written.pdfRepresentation(),
              holder.certificate,
              holder.privateKey,
              Uint8List(0));
          expect(read.getFileEncryptionKey(), written.getFileEncryptionKey());
          expect(read.getEncryptionAlgorithm(),
              entry.value & EncryptionConstants.encryptionMask);
        }
      });

      test('${entry.key} refuses a certificate that is not a recipient',
          () async {
        final written = PdfEncryption.publicKey(
            recipients: [
              PublicKeyRecipientGroup([alice.certificate], 0xFFFFFFFC)
            ],
            encryptionAlgorithm: entry.value);
        expect(
            PdfEncryption.createFromDictionaryWithCertificate(
                written.pdfRepresentation(),
                mallory.certificate,
                mallory.privateKey,
                Uint8List(0)),
            throwsA(isA<PdfException>()));
      });
    }

    test('each recipient group keeps its own permissions', () async {
      const ownerPermissions = 0xFFFFFFFC;
      const readerPermissions = 0xFFFFF0C4;
      final written = PdfEncryption.publicKey(
          recipients: [
            PublicKeyRecipientGroup([alice.certificate], ownerPermissions),
            PublicKeyRecipientGroup([bob.certificate], readerPermissions),
          ],
          encryptionAlgorithm: EncryptionConstants.encryptionAes128);
      final dictionary = written.pdfRepresentation();
      final cf = await dictionary.dictionaryEntry(PdfName.cf);
      final filter =
          await cf!.dictionaryEntry(EncryptionNames.defaultCryptFilter);
      final recipients =
          await filter!.get(EncryptionNames.recipients, true) as PdfArray;
      expect(recipients.size(), 2);

      final aliceView = await PdfEncryption.createFromDictionaryWithCertificate(
          dictionary, alice.certificate, alice.privateKey, Uint8List(0));
      final bobView = await PdfEncryption.createFromDictionaryWithCertificate(
          dictionary, bob.certificate, bob.privateKey, Uint8List(0));
      expect(aliceView.getPermissions(), ownerPermissions);
      expect(bobView.getPermissions(), readerPermissions);
      // The seed is shared, so both views decrypt the same content.
      expect(aliceView.getFileEncryptionKey(), bobView.getFileEncryptionKey());
    });

    test('the file key is the digest of the seed and every recipient object',
        () {
      final seed = Uint8List.fromList(List<int>.generate(20, (i) => i + 1));
      final dictionary = PdfEncryption.publicKey(
        recipients: [
          PublicKeyRecipientGroup([alice.certificate], 0xFFFFFFFC)
        ],
        encryptionAlgorithm: EncryptionConstants.encryptionAes128,
      );
      expect(dictionary.getFileEncryptionKey().length, 16);

      // Recompute 7.6.4.3 by hand with a deterministic seed.
      final handler = PubKeySecurityHandler.create(
        encryptionDictionary: dictionary.pdfRepresentation(),
        groups: [
          PublicKeyRecipientGroup([alice.certificate], 0xFFFFFFFC)
        ],
        encryptionAlgorithm: EncryptionConstants.encryptionAes128,
        seed: seed,
      );
      final digestInput = <int>[...seed];
      for (final recipient in handler.recipients) {
        digestInput.addAll(recipient);
      }
      final expected =
          DigestBytes.compute('SHA1', Uint8List.fromList(digestInput));
      expect(handler.mkey, expected.sublist(0, 16));
    });

    test('leaving the metadata in plaintext adds the 0xFF bytes to the digest',
        () {
      final seed = Uint8List.fromList(List<int>.generate(20, (i) => i + 5));
      final groups = [
        PublicKeyRecipientGroup([alice.certificate], 0xFFFFFFFC)
      ];
      final encrypted = PubKeySecurityHandler.create(
        encryptionDictionary: PdfEncryption().pdfRepresentation(),
        groups: groups,
        encryptionAlgorithm: EncryptionConstants.encryptionAes128,
        seed: seed,
      );
      final digestInput = <int>[...seed, ...encrypted.recipients.first];
      final plain = PubKeySecurityHandler.create(
        encryptionDictionary: PdfEncryption().pdfRepresentation(),
        groups: groups,
        encryptionAlgorithm: EncryptionConstants.encryptionAes128,
        encryptMetadata: false,
        seed: seed,
      );
      expect(plain.mkey, isNot(encrypted.mkey));
      final expected = DigestBytes.compute(
          'SHA1',
          Uint8List.fromList(
              [...seed, ...plain.recipients.first, 0xFF, 0xFF, 0xFF, 0xFF]));
      expect(plain.mkey, expected.sublist(0, 16));
      expect(DigestBytes.compute('SHA1', Uint8List.fromList(digestInput)),
          isNotNull);
    });

    test('embedded files only points /StmF and /StrF at Identity', () async {
      final written = PdfEncryption.publicKey(
          recipients: [
            PublicKeyRecipientGroup([alice.certificate], 0xFFFFFFFC)
          ],
          encryptionAlgorithm: EncryptionConstants.encryptionAes128 |
              EncryptionConstants.embeddedFilesOnly);
      final dictionary = written.pdfRepresentation();
      expect((await dictionary.nameEntry(PdfName.stmF))!.getValue(),
          'Identity');
      expect((await dictionary.nameEntry(PdfName.eff))!.getValue(),
          'DefEmbeddedFile');
      final read = await PdfEncryption.createFromDictionaryWithCertificate(
          dictionary, alice.certificate, alice.privateKey, Uint8List(0));
      expect(read.getFileEncryptionKey(), written.getFileEncryptionKey());
      expect(read.isEmbeddedFilesOnly(), isTrue);
      expect(read.getCryptFilters()!.streamFilter.isIdentity, isTrue);
      expect(read.getCryptFilters()!.embeddedFileFilter.method,
          CryptFilterMethod.aesV2);
    });

    test('content encrypted for a recipient decrypts after reading back',
        () async {
      final written = PdfEncryption.publicKey(
          recipients: [
            PublicKeyRecipientGroup([alice.certificate], 0xFFFFFFFC)
          ],
          encryptionAlgorithm: EncryptionConstants.encryptionAes256);
      final payload = bytes('public-key protected stream payload');
      final encrypted = written.encryptStream(payload, 9, 0);
      final read = await PdfEncryption.createFromDictionaryWithCertificate(
          written.pdfRepresentation(),
          alice.certificate,
          alice.privateKey,
          Uint8List(0));
      expect(read.decryptStream(encrypted, 9, 0), payload);
    });
  });
}
