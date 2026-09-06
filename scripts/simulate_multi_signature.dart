import 'dart:io';
import 'dart:typed_data';
import 'package:pdfcraft/src/pki/pki_utils.dart';

import 'package:pdfcraft/src/sign/pdf_signer.dart';
import 'package:pdfcraft/src/sign/external_signature.dart';
import 'package:pdfcraft/src/sign/signature_mechanism_params.dart';

import 'package:pdfcraft/src/kernel/pdf/pdf_reader.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_writer.dart';
import 'package:pdfcraft/src/layout/document.dart';
import 'package:pdfcraft/src/layout/element/paragraph.dart';

import 'package:pdfcraft/src/layout/properties/property.dart';
import 'package:pdfcraft/src/layout/properties/unit_value.dart';
import 'package:pdfcraft/src/kernel/geom/rectangle.dart' as DpdfGeom;
//C:\mupdf\mutool.exe info .\documento_assinado_04_02_2026.pdf
//C:\mupdf\mutool.exe draw -o page1.png -r 72 documento_assinado_04_02_2026.pdf 1

class LocalExternalSignature implements CraftExternalSignature {
  final RSAPrivateKey key;
  final String digestAlgorithm;

  LocalExternalSignature(this.key, this.digestAlgorithm);

  @override
  String getDigestAlgorithmName() => digestAlgorithm;

  @override
  String getSignatureAlgorithmName() => 'RSA';

  @override
  CraftSignatureMechanismParams? getSignatureMechanismParameters() => null;

  @override
  Future<Uint8List> sign(Uint8List message) async {
    final signer = Signer('${digestAlgorithm}/RSA');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(key));
    final sig = signer.generateSignature(message);
    return sig.bytes;
  }
}

void main() async {
  print('--- Simulação Refinada (Assinatura Visível) ---');

  final filePath =
      r'C:\MyDartProjects\pdfcraft\documento_assinado_04_02_2026.pdf';
  final file = File(filePath);
  if (file.existsSync()) file.deleteSync();

  // 1. Geração da Cadeia de Certificados (Simples para teste)
  print('Gerando certificados...');
  final rootKeyPair = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
  final userKeyPair = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
  final now = DateTime.now();
  final expiry = now.add(Duration(days: 365));

  final rootCertBytes = PkiUtils.createCertificate(
    subjectDN: 'CN=Test Root',
    issuerDN: 'CN=Test Root',
    issuerPrivateKey: rootKeyPair.privateKey as RSAPrivateKey,
    subjectPublicKey: rootKeyPair.publicKey as RSAPublicKey,
    serialNumber: BigInt.from(1),
    notBefore: now,
    notAfter: expiry,
    isCa: true,
  );

  final userCertBytes = PkiUtils.createCertificate(
    subjectDN: 'CN=Test User',
    issuerDN: 'CN=Test Root',
    issuerPrivateKey: rootKeyPair.privateKey as RSAPrivateKey,
    subjectPublicKey: userKeyPair.publicKey as RSAPublicKey,
    serialNumber: BigInt.from(2),
    notBefore: now,
    notAfter: expiry,
    isCa: false,
  );

  final chain = [userCertBytes, rootCertBytes];

  // 2. Criar PDF inicial com texto visível
  print('Criando PDF base...');
  final writer = CraftPdfWriter.toFile(filePath);
  final pdfDoc = await CraftPdfDocument.create(writer);
  final doc = CraftDocument(pdfDoc);

  // Texto grande e repetido
  for (int i = 1; i <= 20; i++) {
    final p = CraftParagraph(
        "Este é o parágrafo número $i de teste do documento assinado.");
    p.setProperty(CraftProperty.FONT_SIZE, CraftUnitValue.createPointValue(14));
    await doc.add(p);
  }

  print('Páginas antes de fechar: ${pdfDoc.pageTotal()}');
  await doc.close();
  await pdfDoc.close();
  print('PDF inicial criado: ${file.lengthSync()} bytes');

  // 3. Aplicar 2 assinaturas VISÍVEIS em sequência
  for (int i = 1; i <= 2; i++) {
    print('\nAplicando assinatura VISÍVEL #$i...');
    final inputBytes = await file.readAsBytes();
    final outputStream = file.openWrite();

    final reader = CraftPdfReader.fromBytes(inputBytes);
    final signer = CraftPdfSigner(reader, outputStream);
    signer.setFieldName('Assinatura_$i');

    // Posicionar assinaturas em locais diferentes
    // Assinatura 1: Esquerda, Assinatura 2: Direita
    double x = (i == 1) ? 50 : 350;
    signer
        .getSignerProperties()
        .setPageRect(DpdfGeom.CraftRectangle(x, 50, 200, 100));
    signer.setReason('Teste de Multi-Assinatura #$i');
    signer.setLocation('Brasil');

    final pks = LocalExternalSignature(
        userKeyPair.privateKey as RSAPrivateKey, 'SHA-256');
    await signer.signDetached(pks, chain);

    print('Assinatura #$i concluída. Novo tamanho: ${file.lengthSync()} bytes');
  }

  print('\n--- Simulação finalizada com sucesso ---');
}
