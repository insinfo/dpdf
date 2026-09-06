import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:dpdf/dpdf.dart';
import 'package:crypto/crypto.dart';

void main() async {
  final outputFile = File('document_compliant_signed.pdf');
  if (outputFile.existsSync()) outputFile.deleteSync();

  print('--- Phase 1: Creating Base PDF with Compliance ---');
  final writer = PdfWriter.toFile(outputFile.path);
  final pdfDoc = PdfDocument.fromWriter(writer);
  
  // 1. Set PDF/A-1B and PDF/UA Conformance
  await pdfDoc.setPdfAConformance();
  pdfDoc.setTagged(); // PDF/UA
  pdfDoc.getCatalog().setDisplayDocTitle(true); // PDF/UA
  
  // 2. Load Font
  final fontName = 'test/assets/arial.ttf';
  final font = PdfFontFactory.createFont(fontName, PdfEncodings.IDENTITY_H, true);
  
  // 3. Add Content
  final page = await pdfDoc.addNewPage();
  final canvas = await PdfCanvas.fromPage(page);
  canvas.beginText();
  await canvas.setFontAndSize(font, 12);
  canvas
      .moveText(50, 800)
      .showText('Este documento é compatível com PDF/A-1B e PDF/UA.')
      .endText();

  // 4. Add OutputIntent with real ICC profile
  final iccFile = File('referencias/pdfcraft-dotnet-develop/pdfcraft.tests/pdfcraft.layout.tests/resources/pdfcraft/layout/ImageColorProfileTest/sRGB_v4_ICC_preference.icc');
  if (iccFile.existsSync()) {
    final iccStream = PdfStream();
    iccStream.setData(iccFile.readAsBytesSync());
    iccStream.makeIndirect(pdfDoc);
    
    final outputIntent = PdfOutputIntent.create(
      'sRGB IEC61966-2.1',
      'sRGB IEC61966-2.1',
      'http://www.color.org',
      'sRGB IEC61966-2.1',
      iccStream,
    );
    pdfDoc.addOutputIntent(outputIntent);
    print('OutputIntent with ICC profile added.');
  }

  await pdfDoc.close();
  print('Base PDF created: ${outputFile.path}');

  print('\n--- Phase 2: Applying First Signature ---');
  await signDocument(outputFile.path, 'document_signed_1.pdf', 'sig1', 'Reason 1');

  print('\n--- Phase 3: Applying Second Signature (Incremental) ---');
  await signDocument('document_signed_1.pdf', 'document_signed_2.pdf', 'sig2', 'Reason 2');

  print('\n--- Phase 4: Verifying Integrity ---');
  await verifyIntegrity('document_signed_2.pdf');
}

Future<void> signDocument(String inputPath, String outputPath, String name, String reason) async {
  final reader = await PdfReader.fromFile(inputPath);
  final writer = PdfWriter.toFile(outputPath);
  
  // PdfSigner always uses append mode by default in this port
  final signer = PdfSigner(reader, writer.getSink());
  
  signer.setFieldName(name);
  signer.setReason(reason);
  signer.setContact('suporte@empresa.com');
  signer.setLocation('Brasil');
  
  // Mock Container
  final container = MockSignatureContainer('SHA-256', 'RSA');
  
  // Load real certificate for PdfPKCS7 (it needs it for structure)
  final certBytes = await loadCert('test/assets/rootRsa.cer');
  final chain = [certBytes];
  
  await signer.signDetached(container, chain, estimatedSize: 8192);
  print('Signed: $outputPath');
  
  // Important: Writer sink should be closed after use
  await writer.getSink().close();
}

Future<Uint8List> loadCert(String path) async {
  final content = await File(path).readAsString();
  final base64Cert = content
      .replaceAll('-----BEGIN CERTIFICATE-----', '')
      .replaceAll('-----END CERTIFICATE-----', '')
      .replaceAll('\n', '')
      .replaceAll('\r', '')
      .trim();
  return base64.decode(base64Cert);
}

Future<void> verifyIntegrity(String path) async {
  final bytes = File(path).readAsBytesSync();
  final content = String.fromCharCodes(bytes);
  
  final rangeRegex = RegExp(r'/ByteRange\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\]');
  final matches = rangeRegex.allMatches(content);
  
  print('Found ${matches.length} signatures.');
  
  int i = 1;
  for (final match in matches) {
    final r1 = int.parse(match.group(1)!);
    final r2 = int.parse(match.group(2)!);
    final r3 = int.parse(match.group(3)!);
    final r4 = int.parse(match.group(4)!);
    
    print('Signature $i ByteRange: [$r1, $r2, $r3, $r4]');
    
    final builder = BytesBuilder();
    builder.add(bytes.sublist(r1, r1 + r2));
    builder.add(bytes.sublist(r3, r3 + r4));
    
    final hash = sha256.convert(builder.toBytes());
    print('  SHA256: $hash');
    
    if (r3 + r4 <= bytes.length) {
       print('  Integrity Check: OK (Range is within file bounds)');
    } else {
       print('  Integrity Check: FAILED (Unexpected range end)');
    }
    i++;
  }
}

class MockSignatureContainer implements IExternalSignature {
  final String digestAlgorithm;
  final String encryptionAlgorithm;

  MockSignatureContainer(this.digestAlgorithm, this.encryptionAlgorithm);

  @override
  String getDigestAlgorithmName() => digestAlgorithm;

  @override
  String getSignatureAlgorithmName() => encryptionAlgorithm;

  @override
  Null getSignatureMechanismParameters() => null;

  @override
  Future<Uint8List> sign(Uint8List message) async {
    // Return dummy signature
    return Uint8List.fromList(List.filled(10, 0x41));
  }
}
