import 'dart:convert';
import 'dart:typed_data';
import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/pki/pki_utils.dart';
import 'package:dpdf/src/sign/signature_mechanism_params.dart';
import 'package:dpdf/src/sign/signature_util.dart';
import 'package:test/test.dart';

void main() {
  late Uint8List broken;
  late Uint8List valid;
  late RSAPrivateKey key;
  late Uint8List certificate;
  setUpAll(() async {
    final bytes = BytesBuilder();
    final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
    await doc.appendBlankPage();
    await doc.close();
    valid = bytes.takeBytes();
    broken = Uint8List.fromList(latin1.encode(latin1
        .decode(valid)
        .replaceFirst(RegExp(r'startxref\s+\d+'), 'startxref\n99999999')));
    final pair = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
    key = pair.privateKey as RSAPrivateKey;
    certificate = PkiUtils.createCertificate(
        subjectDN: 'CN=Recovery test',
        issuerDN: 'CN=Recovery test',
        issuerPrivateKey: key,
        subjectPublicKey: pair.publicKey as RSAPublicKey,
        serialNumber: BigInt.one,
        notBefore: DateTime.utc(2026),
        notAfter: DateTime.utc(2027));
  });
  test(
      'repaired input rejects incremental signing by default before emitting bytes',
      () async {
    final output = BytesBuilder();
    final signer = PdfSigner.fromBytesBuilder(broken, output,
        readerProperties: ReaderProperties()
          ..recoveryMode = PdfRecoveryMode.scan);
    await expectLater(signer.signDetached(_Signature(key), [certificate]),
        throwsFormatException);
    expect(output.length, 0);
  });
  test(
      'explicit full rewrite signs repaired input with valid digest and no dangling Prev',
      () async {
    final output = BytesBuilder();
    final signer = PdfSigner.fromBytesBuilder(broken, output,
        readerProperties: ReaderProperties()
          ..recoveryMode = PdfRecoveryMode.scan,
        repairedSaveMode: PdfRepairedSaveMode.fullRewrite);
    await signer.signDetached(_Signature(key), [certificate]);
    final bytes = output.takeBytes();
    final doc = await PdfDocument.open(PdfReader.fromBytes(bytes));
    expect(doc.wasRepaired, isFalse);
    expect(doc.fileTrailer().containsKey(PdfName.prev), isFalse);
    final signatures = SignatureUtil(doc);
    final names = await signatures.getSignatureNames();
    expect(names, hasLength(1));
    expect(
        (await signatures.readSignatureData(names.single))!.verify(), isTrue);
    await doc.close();
  });
  test('explicit fullRewrite signing works for an unrepaired input', () async {
    final output = BytesBuilder();
    final signer = PdfSigner.fromBytesBuilder(valid, output,
        mode: PdfSigningMode.fullRewrite);
    await signer.signDetached(_Signature(key), [certificate]);
    final doc = await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
    expect(doc.wasRepaired, isFalse);
    expect(doc.fileTrailer().containsKey(PdfName.prev), isFalse);
    final signatures = SignatureUtil(doc);
    final names = await signatures.getSignatureNames();
    expect(
        (await signatures.readSignatureData(names.single))!.verify(), isTrue);
    await doc.close();
  });
  test('incremental editing of repaired input needs explicit rewrite policy',
      () async {
    final output = BytesBuilder();
    final doc = PdfDocument(
        reader: PdfReader.fromBytes(broken,
            ReaderProperties()..recoveryMode = PdfRecoveryMode.skipStreams),
        writer: PdfWriter.fromBytesBuilder(output),
        properties: StampingProperties()
          ..useAppendMode()
          ..repairedSaveMode = PdfRepairedSaveMode.fullRewrite);
    await doc.load();
    expect(doc.wasRepaired, isTrue);
    await doc.appendBlankPage();
    await doc.close();
    final reopened =
        await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
    expect(reopened.pageTotal(), 2);
    expect(reopened.fileTrailer().containsKey(PdfName.prev), isFalse);
    await reopened.close();
  });
}

class _Signature implements ExternalSignature {
  final RSAPrivateKey key;
  _Signature(this.key);
  @override
  String getDigestAlgorithmName() => 'SHA-256';
  @override
  String getSignatureAlgorithmName() => 'RSA';
  @override
  SignatureMechanismParams? getSignatureMechanismParameters() => null;
  @override
  Future<Uint8List> sign(Uint8List bytes) async {
    final signer = Signer('SHA-256/RSA')..init(true, PrivateKeyParameter(key));
    return signer.generateSignature(bytes).bytes;
  }
}
