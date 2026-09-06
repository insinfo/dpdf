import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:pointycastle/export.dart';

import '../../lib/src/pki/pki_utils.dart';

import 'package:dpdf/src/sign/pdf_signer.dart';
import 'package:dpdf/src/sign/i_external_signature.dart';
import 'package:dpdf/src/sign/i_signature_mechanism_params.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/geom/page_size.dart';

/// Simulates the Backend Service which handles keys, certificates and signing
class SimulatedBackend {
  final Map<String, _EncryptedKey> _keyStore = {};

  void storePrivateKey(String userId, RSAPrivateKey key, String password) {
    final salt = PkiUtils.generateRandomBytes(32);
    final keyPem = _encodePrivateKeyToPem(key);
    final derivedKey = PkiUtils.deriveKey(password, salt, 20000);
    // IV for AES
    final iv = PkiUtils.generateRandomBytes(16);
    final encryptedData =
        PkiUtils.processAesCbc(true, derivedKey, iv, utf8.encode(keyPem));

    _keyStore[userId] = _EncryptedKey(encryptedData, salt, iv);
  }

  RSAPrivateKey retrievePrivateKey(String userId, String password) {
    final entry = _keyStore[userId];
    if (entry == null) throw Exception('User not found');

    final derivedKey = PkiUtils.deriveKey(password, entry.salt, 20000);
    final decryptedData =
        PkiUtils.processAesCbc(false, derivedKey, entry.iv, entry.data);

    // Remove padding manually if needed, but PaddedBlockCipherImpl with PKCS7Padding should handle it?
    // PointyCastle's PaddedBlockCipherImpl handles unpadding on decryption.

    final pem = utf8.decode(decryptedData);
    return _parsePrivateKeyFromPem(pem);
  }

  String _encodePrivateKeyToPem(RSAPrivateKey key) {
    // Storing modulus:privateExponent:p:q
    return "FAKE_PEM_CONTENT_FOR_SIMULATION:${key.modulus}:${key.privateExponent}:${key.p}:${key.q}";
  }

  RSAPrivateKey _parsePrivateKeyFromPem(String pem) {
    if (!pem.startsWith("FAKE_PEM_CONTENT")) throw Exception("Invalid PEM");
    final parts = pem.split(':');
    return RSAPrivateKey(
        BigInt.parse(parts[1]),
        BigInt.parse(parts[2]),
        parts[3] != "null" ? BigInt.parse(parts[3]) : null,
        parts[4] != "null" ? BigInt.parse(parts[4]) : null);
  }
}

class _EncryptedKey {
  final Uint8List data;
  final Uint8List salt;
  final Uint8List iv;
  _EncryptedKey(this.data, this.salt, this.iv);
}

class TestExternalSignature implements IExternalSignature {
  final RSAPrivateKey key;
  final String digestAlgorithm;

  TestExternalSignature(this.key, this.digestAlgorithm);

  @override
  String getDigestAlgorithmName() => digestAlgorithm;

  @override
  String getSignatureAlgorithmName() => 'RSA';

  @override
  ISignatureMechanismParams? getSignatureMechanismParameters() => null;

  @override
  Future<Uint8List> sign(Uint8List message) async {
    final signer = Signer('${digestAlgorithm}/RSA');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(key));
    final sig = signer.generateSignature(message);
    if (sig is RSASignature) {
      return sig.bytes;
    }
    throw Exception('Signing failed');
  }
}

class _IOSinkWrapper implements IOSink {
  final BytesBuilder builder;
  _IOSinkWrapper(this.builder);
  @override
  void add(List<int> data) => builder.add(data);
  @override
  Future close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Expanded PKI Simulation', () {
    late SimulatedBackend backend;

    late AsymmetricKeyPair rootKey;
    late Uint8List rootCert;
    late AsymmetricKeyPair userKey;
    late Uint8List userCert;

    setUpAll(() {
      backend = SimulatedBackend();

      // 1. Setup PKI
      rootKey = PkiUtils.generateRSAKeyPair();
      rootCert = PkiUtils.createCertificate(
          subjectDN: 'CN=Root CA',
          issuerDN: 'CN=Root CA',
          issuerPrivateKey: rootKey.privateKey as RSAPrivateKey,
          subjectPublicKey: rootKey.publicKey as RSAPublicKey,
          serialNumber: BigInt.one,
          notBefore: DateTime.now(),
          notAfter: DateTime.now().add(Duration(days: 365)),
          isCa: true);

      userKey = PkiUtils.generateRSAKeyPair();
      userCert = PkiUtils.createCertificate(
          subjectDN: 'CN=User',
          issuerDN: 'CN=Root CA',
          issuerPrivateKey: rootKey.privateKey as RSAPrivateKey,
          subjectPublicKey: userKey.publicKey as RSAPublicKey,
          serialNumber: BigInt.from(100),
          notBefore: DateTime.now(),
          notAfter: DateTime.now().add(Duration(days: 365)),
          isCa: false);
    });

    test('Secure Storage of Private Key', () {
      final password = "MySecurePassword123";
      // Store
      backend.storePrivateKey(
          "user1", userKey.privateKey as RSAPrivateKey, password);

      // Retrieve
      final retrievedKey = backend.retrievePrivateKey("user1", password);

      expect(retrievedKey.modulus,
          equals((userKey.privateKey as RSAPrivateKey).modulus));
    });

    test('Full Signing Workflow (Internal + External)', () async {
      final password = "MySecurePassword123";
      backend.storePrivateKey(
          "user1", userKey.privateKey as RSAPrivateKey, password);

      // 1. Create PDF
      final initialPdf = await _createDummyPdf();
      expect(initialPdf.length, greaterThan(0));

      // 2. Sign Internal (First Signature)
      // Retrieve key securely
      final privKey = backend.retrievePrivateKey("user1", password);

      final signedPdf1 =
          await _signPdf(initialPdf, privKey, [userCert, rootCert], "Sig1");

      // Verify signature 1 is readable
      try {
        final rtmp = PdfReader.fromBytes(signedPdf1);
        final dtmp = PdfDocument(reader: rtmp);
        await dtmp.load();
        expect(dtmp.getPagesTree().getNumberOfPages(), greaterThan(0));
      } catch (e) {
        rethrow;
      }
      expect(signedPdf1.length, greaterThan(initialPdf.length));

      // 3. Sign External (Second Signature) - Now works with append mode!
      // Each signature creates a new PDF revision incrementally added to the end
      final signedPdf2 =
          await _signPdf(signedPdf1, privKey, [userCert, rootCert], "Sig2");
      expect(signedPdf2.length, greaterThan(signedPdf1.length));
    });
  });
}

Future<Uint8List> _createDummyPdf() async {
  final output = BytesBuilder();
  final writer = PdfWriter(_IOSinkWrapper(output));
  final pdf = PdfDocument(writer: writer);
  await pdf.addNewPage(PageSize.A4);
  await pdf.close();
  return output.toBytes();
}

Future<Uint8List> _signPdf(Uint8List inputPdf, RSAPrivateKey privKey,
    List<Uint8List> chain, String fieldName) async {
  final output = BytesBuilder();
  final sink = _IOSinkWrapper(output);
  final reader = PdfReader.fromBytes(inputPdf);
  final signer = PdfSigner(reader, sink);

  // Set different field name to avoid collision if append mode works/is used
  signer.setFieldName(fieldName);

  await signer.signDetached(
    TestExternalSignature(privKey, 'SHA-256'),
    chain,
  );

  return output.toBytes();
}
