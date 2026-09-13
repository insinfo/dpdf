import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/commons/digest/digest_bytes.dart';
import 'package:dpdf/src/kernel/crypto/crypt_filter.dart';
import 'package:dpdf/src/kernel/crypto/crypt_filter_cipher.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:pointycastle/export.dart' as oracle;
import 'package:test/test.dart';

Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

CryptFilter filterOf(CryptFilterMethod method, {int? length}) =>
    CryptFilter(name: PdfName.stdCF, method: method, length: length);

void main() {
  final fileKey128 =
      Uint8List.fromList(List<int>.generate(16, (i) => (i * 13 + 5) & 0xFF));
  final fileKey40 = Uint8List.fromList(fileKey128.sublist(0, 5));
  final fileKey256 =
      Uint8List.fromList(List<int>.generate(32, (i) => (i * 29 + 11) & 0xFF));

  group('Algorithm 1 object keys', () {
    test('V2 appends the object and generation numbers before the MD5 hash',
        () {
      final cipher =
          CryptFilterCipher(filterOf(CryptFilterMethod.v2), fileKey128);
      final key = cipher.objectKey(0x030201, 0x0504);
      final input =
          Uint8List.fromList([...fileKey128, 0x01, 0x02, 0x03, 0x04, 0x05]);
      final expected = DigestBytes.compute('MD5', input);
      expect(key, expected.sublist(0, 16));
    });

    test('AESV2 additionally appends the sAlT bytes', () {
      final cipher =
          CryptFilterCipher(filterOf(CryptFilterMethod.aesV2), fileKey128);
      final key = cipher.objectKey(1, 0);
      final input = Uint8List.fromList([
        ...fileKey128,
        1,
        0,
        0,
        0,
        0,
        0x73,
        0x41,
        0x6c,
        0x54,
      ]);
      expect(key, DigestBytes.compute('MD5', input).sublist(0, 16));
    });

    test('a 40-bit key yields a 10-byte object key', () {
      final cipher =
          CryptFilterCipher(filterOf(CryptFilterMethod.v2), fileKey40);
      expect(cipher.objectKey(7, 0).length, 10);
      expect(cipher.objectKeySize(), 10);
    });

    test('AESV3 uses the 256-bit file key as is', () {
      final cipher =
          CryptFilterCipher(filterOf(CryptFilterMethod.aesV3), fileKey256);
      expect(cipher.objectKey(42, 3), fileKey256);
      expect(cipher.objectKey(1, 0), cipher.objectKey(9999, 7));
    });

    test('different objects derive different keys', () {
      final cipher =
          CryptFilterCipher(filterOf(CryptFilterMethod.aesV2), fileKey128);
      expect(cipher.objectKey(1, 0), isNot(cipher.objectKey(2, 0)));
      expect(cipher.objectKey(1, 0), isNot(cipher.objectKey(1, 1)));
    });
  });

  group('Symmetric round trips', () {
    final payload = bytes('Encryption of data using RC4 or AES, 7.6.2.');

    test('V2 round trips and matches the RC4 oracle', () {
      final cipher =
          CryptFilterCipher(filterOf(CryptFilterMethod.v2), fileKey128);
      final encrypted = cipher.encrypt(payload, 12, 0);
      expect(encrypted.length, payload.length);
      expect(cipher.decrypt(encrypted, 12, 0), payload);

      final rc4 = oracle.RC4Engine()
        ..init(true, oracle.KeyParameter(cipher.objectKey(12, 0)));
      expect(encrypted, rc4.process(payload));
    });

    for (final method in [CryptFilterMethod.aesV2, CryptFilterMethod.aesV3]) {
      test('$method stores a 16-byte initialisation vector and pads to 16', () {
        final key = method == CryptFilterMethod.aesV3 ? fileKey256 : fileKey128;
        final cipher = CryptFilterCipher(filterOf(method), key);
        final encrypted = cipher.encrypt(payload, 5, 0);
        expect(encrypted.length % 16, 0);
        expect(encrypted.length, 16 + ((payload.length ~/ 16) + 1) * 16);
        expect(cipher.decrypt(encrypted, 5, 0), payload);

        final objectKey = cipher.objectKey(5, 0);
        final iv = Uint8List.fromList(encrypted.sublist(0, 16));
        final pc = oracle.PaddedBlockCipherImpl(
            oracle.PKCS7Padding(), oracle.CBCBlockCipher(oracle.AESEngine()));
        pc.init(
            true,
            oracle.PaddedBlockCipherParameters(
                oracle.ParametersWithIV(oracle.KeyParameter(objectKey), iv),
                null));
        expect(encrypted.sublist(16), pc.process(payload));
      });

      test('$method uses a fresh initialisation vector on every call', () {
        final key = method == CryptFilterMethod.aesV3 ? fileKey256 : fileKey128;
        final cipher = CryptFilterCipher(filterOf(method), key);
        final first = cipher.encrypt(payload, 5, 0);
        final second = cipher.encrypt(payload, 5, 0);
        expect(first.sublist(0, 16), isNot(second.sublist(0, 16)));
        expect(cipher.decrypt(second, 5, 0), payload);
      });

      test('$method pads a message whose length is a multiple of 16', () {
        final key = method == CryptFilterMethod.aesV3 ? fileKey256 : fileKey128;
        final cipher = CryptFilterCipher(filterOf(method), key);
        final block = Uint8List.fromList(List<int>.generate(32, (i) => i));
        final encrypted = cipher.encrypt(block, 3, 0);
        // 7.6.2: "the pad is present when M is evenly divisible by 16".
        expect(encrypted.length, 16 + 48);
        expect(cipher.decrypt(encrypted, 3, 0), block);
      });
    }

    test('an empty message still round trips through AES', () {
      final cipher =
          CryptFilterCipher(filterOf(CryptFilterMethod.aesV2), fileKey128);
      final encrypted = cipher.encrypt(Uint8List(0), 1, 0);
      expect(encrypted.length, 32);
      expect(cipher.decrypt(encrypted, 1, 0), isEmpty);
    });

    test('Identity passes the data through unchanged', () {
      final cipher = CryptFilterCipher(CryptFilter.identity, fileKey128);
      expect(cipher.isPassThrough, isTrue);
      expect(cipher.encrypt(payload, 1, 0), payload);
      expect(cipher.decrypt(payload, 1, 0), payload);
    });

    test('None leaves the data to the security handler', () {
      final cipher =
          CryptFilterCipher(filterOf(CryptFilterMethod.none), fileKey128);
      expect(cipher.isPassThrough, isTrue);
      expect(cipher.encrypt(payload, 1, 0), payload);
    });

    test('an explicit key bypasses Algorithm 1, as 7.4.10 requires', () {
      final cipher =
          CryptFilterCipher(filterOf(CryptFilterMethod.aesV3), fileKey256);
      final encrypted = cipher.encryptWithKey(payload, fileKey256);
      expect(cipher.decryptWithKey(encrypted, fileKey256), payload);
    });
  });

  group('Crypt filter dictionaries', () {
    test('every CFM name of Table 25 round trips', () async {
      for (final method in CryptFilterMethod.values) {
        final filter = CryptFilter(name: PdfName.stdCF, method: method);
        final parsed = await CryptFilter.fromDictionary(
            PdfName.stdCF, filter.toDictionary());
        expect(parsed.method, method);
      }
    });

    test('an unknown CFM is reported as unsupported', () {
      final dictionary = PdfDictionary();
      dictionary.put(PdfName.cfm, PdfName.intern('AESV9'));
      expect(CryptFilter.fromDictionary(PdfName.stdCF, dictionary),
          throwsA(isA<PdfException>()));
    });

    test('a missing CFM defaults to None', () async {
      final parsed =
          await CryptFilter.fromDictionary(PdfName.stdCF, PdfDictionary());
      expect(parsed.method, CryptFilterMethod.none);
      expect(parsed.authEvent.getValue(), 'DocOpen');
      expect(parsed.encryptMetadata, isTrue);
    });

    test('/Length is read in bytes or in bits', () {
      expect(
          CryptFilter(
                  name: PdfName.stdCF,
                  method: CryptFilterMethod.aesV2,
                  length: 16)
              .keyLengthInBits(40),
          128);
      expect(
          CryptFilter(
                  name: PdfName.stdCF,
                  method: CryptFilterMethod.aesV2,
                  length: 128)
              .keyLengthInBits(40),
          128);
      expect(
          CryptFilter(name: PdfName.stdCF, method: CryptFilterMethod.aesV3)
              .keyLengthInBits(40),
          256);
    });

    test('/Recipients and /EncryptMetadata of Table 27 round trip', () async {
      final recipient = bytes('a pkcs7 object');
      final filter = CryptFilter(
        name: PdfName.intern('DefaultCryptFilter'),
        method: CryptFilterMethod.aesV2,
        length: 128,
        encryptMetadata: false,
        recipients: [recipient],
      );
      final parsed =
          await CryptFilter.fromDictionary(filter.name, filter.toDictionary());
      expect(parsed.recipients.single, recipient);
      expect(parsed.encryptMetadata, isFalse);
    });

    test('a /Recipients string is accepted as a single object', () async {
      final dictionary = PdfDictionary();
      dictionary.put(PdfName.cfm, PdfName.aesV2);
      dictionary.put(EncryptionNames.recipients,
          PdfString.fromBytes(bytes('single'), true));
      final parsed =
          await CryptFilter.fromDictionary(PdfName.stdCF, dictionary);
      expect(parsed.recipients.single, bytes('single'));
    });
  });

  group('Crypt filter configuration', () {
    Future<CryptFilterConfiguration> build(
        {PdfName? stmF, PdfName? strF, PdfName? eff}) async {
      final stdcf = PdfDictionary();
      stdcf.put(PdfName.cfm, PdfName.aesV2);
      stdcf.put(PdfName.length, PdfNumber.fromInt(16));
      final efcf = PdfDictionary();
      efcf.put(PdfName.cfm, PdfName.v2);
      efcf.put(PdfName.authEvent, PdfName.efOpen);
      final cf = PdfDictionary();
      cf.put(PdfName.stdCF, stdcf);
      cf.put(PdfName.intern('EFCF'), efcf);
      final dictionary = PdfDictionary();
      dictionary.put(PdfName.cf, cf);
      if (stmF != null) dictionary.put(PdfName.stmF, stmF);
      if (strF != null) dictionary.put(PdfName.strF, strF);
      if (eff != null) dictionary.put(PdfName.eff, eff);
      return CryptFilterConfiguration.fromEncryptionDictionary(dictionary);
    }

    test('/StmF and /StrF default to Identity', () async {
      final configuration = await build();
      expect(configuration.streamFilter.isIdentity, isTrue);
      expect(configuration.stringFilter.isIdentity, isTrue);
      expect(configuration.filters.keys, containsAll(['StdCF', 'EFCF']));
    });

    test('/StmF and /StrF may select different filters', () async {
      final configuration =
          await build(stmF: PdfName.stdCF, strF: PdfName.identity);
      expect(configuration.streamFilter.method, CryptFilterMethod.aesV2);
      expect(configuration.stringFilter.isIdentity, isTrue);
    });

    test('/EFF falls back to /StmF when absent', () async {
      final configuration = await build(stmF: PdfName.stdCF);
      expect(configuration.embeddedFileFilter.name.getValue(), 'StdCF');
    });

    test('/EFF selects its own filter when present', () async {
      final configuration =
          await build(stmF: PdfName.stdCF, eff: PdfName.intern('EFCF'));
      expect(configuration.embeddedFileFilter.method, CryptFilterMethod.v2);
      expect(configuration.embeddedFileFilter.authEvent.getValue(), 'EFOpen');
    });

    test('an unknown /StmF name falls back to Identity', () async {
      final configuration = await build(stmF: PdfName.intern('Missing'));
      expect(configuration.streamFilter.isIdentity, isTrue);
    });

    test('the example of 7.6.5 keeps metadata readable', () async {
      // The metadata stream of the example carries /Filter [/Crypt] with a
      // decode parameters dictionary naming /Identity.
      final configuration = await build(stmF: PdfName.stdCF);
      final decodeParms = PdfDictionary();
      decodeParms.put(PdfName.type, EncryptionNames.cryptFilterDecodeParms);
      decodeParms.put(EncryptionNames.name, PdfName.identity);
      final named = await decodeParms.nameEntry(EncryptionNames.name);
      expect(configuration.byName(named)!.isIdentity, isTrue);
      final filters = PdfArray();
      filters.add(PdfName.crypt);
      expect(filters.size(), 1);
      expect(PdfBoolean.pdfFalse.getValue(), isFalse);
    });
  });
}
