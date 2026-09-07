import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/pki/pki_utils.dart';
import 'package:dpdf/src/sign/signature_mechanism_params.dart';
import 'package:dpdf/src/sign/signature_util.dart';

import 'package:test/test.dart';

void main() {
  test('in-memory incremental signature survives reopen and rejects tampering',
      () async {
    final base = BytesBuilder();
    final document = PdfDocument.create(PdfWriter.fromBytesBuilder(base));
    await document.appendBlankPage();
    await document.close();
    final input = base.takeBytes();
    // Ephemeral key used only to exercise the integration, not a trust identity.
    final keys = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
    final privateKey = keys.privateKey as RSAPrivateKey;
    final certificate = PkiUtils.createCertificate(
      subjectDN: 'CN=DPDF platform test',
      issuerDN: 'CN=DPDF platform test',
      issuerPrivateKey: privateKey,
      subjectPublicKey: keys.publicKey as RSAPublicKey,
      serialNumber: BigInt.one,
      notBefore: DateTime.utc(2026),
      notAfter: DateTime.utc(2027),
    );
    final output = BytesBuilder();
    final signer = PdfSigner.fromBytesBuilder(input, output);
    await signer.signDetached(_LocalSignature(privateKey), [certificate]);

    final bytes = output.takeBytes();
    Future<bool> verify(Uint8List data) async {
      final opened = await PdfDocument.open(PdfReader.fromBytes(data));
      try {
        final util = SignatureUtil(opened);
        final names = await util.getSignatureNames();
        expect(names, hasLength(1));
        return (await util.readSignatureData(names.single))!.verify();
      } finally {
        await opened.close();
      }
    }

    expect(await verify(bytes), isTrue);
    final altered = Uint8List.fromList(bytes);
    // PDF version remains parseable but is covered by the signed byte range.
    altered[7] = altered[7] == 55 ? 54 : 55;
    expect(await verify(altered), isFalse);
  });
}

class _LocalSignature implements ExternalSignature {
  final RSAPrivateKey key;
  _LocalSignature(this.key);
  @override
  String getDigestAlgorithmName() => 'SHA-256';
  @override
  String getSignatureAlgorithmName() => 'RSA';
  @override
  SignatureMechanismParams? getSignatureMechanismParameters() => null;
  @override
  Future<Uint8List> sign(Uint8List message) async {
    final signer = Signer('SHA-256/RSA')..init(true, PrivateKeyParameter(key));
    return signer.generateSignature(message).bytes;
  }
}
