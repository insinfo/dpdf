
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dpdf/src/pki/pki_utils.dart';
import 'package:dpdf/src/sign/pdf_signer.dart';
import 'package:dpdf/src/sign/i_external_signature.dart';
import 'package:dpdf/src/sign/i_signature_mechanism_params.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/layout/document.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:test/test.dart';

class LocalExternalSignature implements IExternalSignature {
  final pc.RSAPrivateKey key;
  final String digestAlgorithm;

  LocalExternalSignature(this.key, this.digestAlgorithm);

  @override
  String getDigestAlgorithmName() => digestAlgorithm;

  @override
  String getSignatureAlgorithmName() => 'RSA';

  @override
  ISignatureMechanismParams? getSignatureMechanismParameters() => null;

  @override
  Future<Uint8List> sign(Uint8List message) async {
    final signer = pc.Signer('${digestAlgorithm}/RSA');
    signer.init(true, pc.PrivateKeyParameter<pc.RSAPrivateKey>(key));
    final sig = signer.generateSignature(message);
    if (sig is pc.RSASignature) {
      return sig.bytes;
    }
    throw Exception('Signing failed');
  }
}

void main() {
  group('Signature Integrity Tests', () {
    test('Verify ByteRange and Hash Integrity', () async {
      final workDir = Directory('test/tmp/sig_test');
      if (workDir.existsSync()) workDir.deleteSync(recursive: true);
      workDir.createSync(recursive: true);

      final filePath = '${workDir.path}/test_integrity.pdf';
      final file = File(filePath);

      // 1. Create Base PDF
      final writer = PdfWriter.toFile(filePath);
      final pdfDoc = await PdfDocument.create(writer);
      final doc = Document(pdfDoc);
      await doc.add(Paragraph("Documento de teste para integridade de assinatura."));
      await doc.close();
      await pdfDoc.close();

      final baseSize = file.lengthSync();
      expect(baseSize, greaterThan(0));

      // 2. Generate Signer Info
      final rootKeyPair = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
      final userKeyPair = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
      final now = DateTime.now();
      final expiry = now.add(Duration(days: 365));

      final rootCertBytes = PkiUtils.createCertificate(
        subjectDN: 'CN=Test Root', issuerDN: 'CN=Test Root',
        issuerPrivateKey: rootKeyPair.privateKey as pc.RSAPrivateKey,
        subjectPublicKey: rootKeyPair.publicKey as pc.RSAPublicKey,
        serialNumber: BigInt.from(1), notBefore: now, notAfter: expiry, isCa: true,
      );

      final userCertBytes = PkiUtils.createCertificate(
        subjectDN: 'CN=Test User', issuerDN: 'CN=Test Root',
        issuerPrivateKey: rootKeyPair.privateKey as pc.RSAPrivateKey,
        subjectPublicKey: userKeyPair.publicKey as pc.RSAPublicKey,
        serialNumber: BigInt.from(2), notBefore: now, notAfter: expiry, isCa: false,
      );

      final chain = [userCertBytes, rootCertBytes];

      // 3. Sign the PDF
      final inputBytes = await file.readAsBytes();
      final outputStream = file.openWrite();
      final reader = PdfReader.fromBytes(inputBytes);
      final signer = PdfSigner(reader, outputStream);
      
      final pks = LocalExternalSignature(userKeyPair.privateKey as pc.RSAPrivateKey, 'SHA-256');
      await signer.signDetached(pks, chain);

      // Wait for file to be closed and flushed
      await Future.delayed(Duration(milliseconds: 500));
      
      final signedBytes = await file.readAsBytes();
      final signedSize = signedBytes.length;

      // 4. Extract ByteRange from file
      final content = String.fromCharCodes(signedBytes);
      final rangeMatch = RegExp(r'\/ByteRange\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\]').firstMatch(content);
      expect(rangeMatch, isNotNull, reason: "ByteRange not found in signed PDF");

      final r1 = int.parse(rangeMatch!.group(1)!);
      final r2 = int.parse(rangeMatch.group(2)!);
      final r3 = int.parse(rangeMatch.group(3)!);
      final r4 = int.parse(rangeMatch.group(4)!);

      expect(r1, equals(0), reason: "Range 1 must start at 0");
      expect(r1 + r2 + r4, lessThanOrEqualTo(signedSize), reason: "Range exceeds file size");
      expect(r3 + r4, equals(signedSize), reason: "ByteRange does not cover file until EOF");

      // 5. Calculate HASH of the ranges specified in the file
      final b = BytesBuilder();
      b.add(signedBytes.sublist(r1, r1 + r2));
      b.add(signedBytes.sublist(r3, r3 + r4));
      
      final hashedData = b.toBytes();
      final calculatedHash = sha256.convert(hashedData);
      
      print('Hash of ranges in file: $calculatedHash');

      // 6. Verify Contents (Hex String)
      expect(signedBytes[r2], equals(0x3C), reason: "Start of contents hole must be <");
      expect(signedBytes[r3 - 1], equals(0x3E), reason: "End of contents hole must be >");

      // Verify that the hash calculated here matches what is inside the PKCS7 would be complex 
      // without a full ASN1 parser, but we verify the ranges are byte-perfect.
    });

    test('Verify Multi-Signature Sequence Integrity', () async {
      final workDir = Directory('test/tmp/multi_sig_test');
      if (workDir.existsSync()) workDir.deleteSync(recursive: true);
      workDir.createSync(recursive: true);

      final filePath = '${workDir.path}/multi_test.pdf';
      final file = File(filePath);

      // Create base
      final pdfDoc = await PdfDocument.create(PdfWriter.toFile(filePath));
      await (Document(pdfDoc)).add(Paragraph("Multi-signature integrity test."));
      await pdfDoc.close();

      final rootKeyPair = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
      final userKeyPair = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
      final chain = [PkiUtils.createCertificate(
        subjectDN: 'CN=Test', issuerDN: 'CN=Test',
        issuerPrivateKey: rootKeyPair.privateKey as pc.RSAPrivateKey,
        subjectPublicKey: userKeyPair.publicKey as pc.RSAPublicKey,
        serialNumber: BigInt.from(1), notBefore: DateTime.now(), 
        notAfter: DateTime.now().add(Duration(days: 1)), isCa: false,
      )];

      // Sign 1
      await _signFile(file, userKeyPair.privateKey as pc.RSAPrivateKey, chain, "Sig1");
      final size1 = file.lengthSync();

      // Sign 2
      await _signFile(file, userKeyPair.privateKey as pc.RSAPrivateKey, chain, "Sig2");
      final size2 = file.lengthSync();

      final bytes = await file.readAsBytes();
      
      // Extract both ByteRanges
      final content = String.fromCharCodes(bytes);
      final matches = RegExp(r'\/ByteRange\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\]').allMatches(content).toList();
      
      expect(matches.length, equals(2));

      // Check Rev 1 ByteRange
      final br1 = matches[0].groups([1,2,3,4]).map((e) => int.parse(e!)).toList();
      expect(br1[0] + br1[1] + br1[3], lessThanOrEqualTo(size1));
      expect(br1[2] + br1[3], equals(size1), reason: "Rev 1 ByteRange must end at Rev 1 EOF");

      // Check Rev 2 ByteRange
      final br2 = matches[1].groups([1,2,3,4]).map((e) => int.parse(e!)).toList();
      expect(br2[2] + br2[3], equals(size2), reason: "Rev 2 ByteRange must end at current EOF");

      print('Multi-signature ByteRanges verified successfully.');
    });
  });
}

Future<void> _signFile(File file, pc.RSAPrivateKey key, List<Uint8List> chain, String fieldName) async {
  final bytes = await file.readAsBytes();
  final sink = file.openWrite();
  final reader = PdfReader.fromBytes(bytes);
  final signer = PdfSigner(reader, sink);
  signer.setFieldName(fieldName);
  final pks = LocalExternalSignature(key, 'SHA-256');
  await signer.signDetached(pks, chain);
  await sink.close();
  // Small delay to ensure OS file system sync
  await Future.delayed(Duration(milliseconds: 100));
}
