import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:pointycastle/export.dart';

import '../../lib/src/pki/pki_utils.dart';
import 'mock_servers.dart';

import 'package:dpdf/src/sign/pdf_signer.dart';
import 'package:dpdf/src/sign/i_signature_mechanism_params.dart';

import 'package:dpdf/src/sign/i_external_signature.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';

import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';

import 'package:dpdf/src/kernel/geom/page_size.dart';

class SimpleExternalSignature implements IExternalSignature {
  final RSAPrivateKey key;
  final String digestAlgorithm;

  SimpleExternalSignature(this.key, this.digestAlgorithm);

  @override
  String getDigestAlgorithmName() => digestAlgorithm;

  @override
  String getSignatureAlgorithmName() => 'RSA';

  @override
  ISignatureMechanismParams? getSignatureMechanismParameters() =>
      null; // Fix method name

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

void main() {
  group('PKI Simulation', () {
    late AsymmetricKeyPair rootKey;
    late Uint8List rootCert;

    late AsymmetricKeyPair interKey;
    late Uint8List interCert;

    late AsymmetricKeyPair userKey;
    late Uint8List userCert;

    late MockTsaServer tsaServer;
    late MockOcspServer ocspServer;

    setUpAll(() async {
      // 1. Generate Root CA
      rootKey = PkiUtils.generateRSAKeyPair();
      rootCert = PkiUtils.createCertificate(
        subjectDN: 'CN=Root CA,O=Test Org,C=US',
        issuerDN: 'CN=Root CA,O=Test Org,C=US',
        issuerPrivateKey: rootKey.privateKey as RSAPrivateKey,
        subjectPublicKey: rootKey.publicKey as RSAPublicKey,
        serialNumber: BigInt.one,
        notBefore: DateTime.now().subtract(Duration(days: 1)),
        notAfter: DateTime.now().add(Duration(days: 3650)),
        isCa: true,
      );

      // 2. Generate Intermediate CA
      interKey = PkiUtils.generateRSAKeyPair();
      interCert = PkiUtils.createCertificate(
        subjectDN: 'CN=Intermediate CA,O=Test Org,C=US',
        issuerDN: 'CN=Root CA,O=Test Org,C=US',
        issuerPrivateKey: rootKey.privateKey as RSAPrivateKey,
        subjectPublicKey: interKey.publicKey as RSAPublicKey,
        serialNumber: BigInt.from(2),
        notBefore: DateTime.now(),
        notAfter: DateTime.now().add(Duration(days: 365)),
        isCa: true,
      );

      // 3. Generate User Cert
      userKey = PkiUtils.generateRSAKeyPair();
      userCert = PkiUtils.createCertificate(
        subjectDN: 'CN=Alice User,O=Test Org,C=US',
        issuerDN: 'CN=Intermediate CA,O=Test Org,C=US',
        issuerPrivateKey: interKey.privateKey as RSAPrivateKey,
        subjectPublicKey: userKey.publicKey as RSAPublicKey,
        serialNumber: BigInt.from(100),
        notBefore: DateTime.now(),
        notAfter: DateTime.now().add(Duration(days: 90)),
        isCa: false,
      );

      // 4. Start Servers
      tsaServer = MockTsaServer(
          8899, rootKey, rootCert); // Using root key for simple TSA
      await tsaServer.start();

      ocspServer = MockOcspServer(8888);
      await ocspServer.start();
    });

    tearDownAll(() async {
      try {
        await tsaServer.stop();
      } catch (_) {}
      try {
        await ocspServer.stop();
      } catch (_) {}
    });

    test('Sign PDF with User Certificate and Chain', () async {
      // Create a dummy PDF
      final pdfBytes = await _createDummyPdf();

      final output = BytesBuilder();
      final sink =
          _IOSinkWrapper(output); // Needed wrapper? IOSink implementation

      // Load into PdfReader
      final reader = PdfReader.fromBytes(pdfBytes);

      final signer = PdfSigner(reader, sink);

      final chain = [userCert, interCert, rootCert];

      await signer.signDetached(
        SimpleExternalSignature(userKey.privateKey as RSAPrivateKey, 'SHA-256'),
        chain,
        // tsaClient: ... // Need TSA Client implementation linking to localhost:8899
        // ocspClient: ...
      );

      // Check output
      expect(output.length, greaterThan(pdfBytes.length));

      // Verify (Basic check if PdfPKCS7 can parse it)
      // ...
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

class _IOSinkWrapper implements IOSink {
  final BytesBuilder builder;
  _IOSinkWrapper(this.builder);

  @override
  void add(List<int> data) => builder.add(data);

  @override
  Future close() async {}

  // ... implement other members stub ...
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
