import 'dart:convert';
import 'keystore_smoke.dart' as keystores;
import 'package:dpdf/src/kernel/pdf/pdf_date.dart';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dpdf/dpdf_platform.dart';
import 'package:dpdf/src/io/codec/ccitt_g4_encoder.dart';
import 'package:dpdf/src/io/codec/tiff_fax_decoder.dart';
import 'package:dpdf/src/io/codec/png_writer.dart';
import 'package:dpdf/src/pki/pki_utils.dart';
import 'package:dpdf/src/sign/signature_mechanism_params.dart';
import 'package:dpdf/src/sign/signature_util.dart';

/// Portable integration check. No filesystem or browser DOM is required.
Future<void> main() async {
  keystores.main();
  if (CraftPdfDate.decode("D:20260827143000-03'00'") !=
      DateTime.utc(2026, 8, 27, 17, 30)) {
    throw StateError('PDF date lost its declared UTC offset');
  }
  final marker = Uint8List(2048)..setRange(0, 9, ascii.encode('startxref'));
  if (CraftPdfTokenizer(CraftRandomAccessFileOrArray(marker)).getStartxref() !=
      0) {
    throw StateError('Reverse marker search skipped the first bytes');
  }
  _checkCodecs();
  final text = CraftPdfEncodings.convertToString(
      Uint8List.fromList([0x80, 0xa0]), CraftPdfEncodings.PDF_DOC_ENCODING);
  if (text != '•€') throw StateError('PDFDocEncoding conversion failed');
  await _checkFormExtraction();
  final word = CraftRandomAccessFileOrArray(
          Uint8List.fromList([127, 255, 255, 255, 255, 255, 255, 255]))
      .readBigInt64();
  if (word != (BigInt.one << 63) - BigInt.one) {
    throw StateError('64-bit platform backend lost precision');
  }
  final buffer = BytesBuilder();
  final document =
      CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(buffer));
  final page = await document.appendBlankPage();
  final font = CraftPdfDictionary()
    ..put(CraftPdfName.type, CraftPdfName.font)
    ..put(CraftPdfName.subtype, CraftPdfName('Type1'))
    ..put(CraftPdfName.baseFont, CraftPdfName('Helvetica'))
    ..put(CraftPdfName.encoding, CraftPdfName('WinAnsiEncoding'));
  final alternate = CraftPdfDictionary()
    ..put(CraftPdfName.type, CraftPdfName.font)
    ..put(CraftPdfName.subtype, CraftPdfName('Type1'))
    ..put(CraftPdfName.baseFont, CraftPdfName('Courier'))
    ..put(CraftPdfName.encoding, CraftPdfName('WinAnsiEncoding'));
  page.pdfRepresentation().put(
      CraftPdfName.resources,
      CraftPdfDictionary()
        ..put(
            CraftPdfName.font,
            CraftPdfDictionary()
              ..put(CraftPdfName('F1'), font)
              ..put(CraftPdfName('Alternate'), alternate)));
  page.pdfRepresentation().put(
      CraftPdfName.contents,
      CraftPdfStream.withBytes(
          Uint8List.fromList(ascii.encode(
              'BT /F1 18 Tf 50 750 Td (Cliente: Pe) Tj /Alternate 18 Tf (dro. Total: 100.) Tj ET')),
          0));
  // This fixture has no metadata by design. Do not strip metadata from an
  // arbitrary input document to circumvent the editing API's validation.
  (await document.documentDetails()).pdfRepresentation().clear();
  await document.close();

  final edited = await PdfTextEditing.replace(
      buffer.takeBytes(), [const PdfTextReplacement(1, 'Pedro', 'João')]);
  final reopened =
      await CraftPdfDocument.open(CraftPdfReader.fromBytes(edited));
  try {
    final text = await PdfTextExtraction.fromPage((await reopened.pageAt(1))!);
    if (!text.contains('João') || text.contains('Pedro')) {
      throw StateError('Text editing round trip failed: $text');
    }
  } finally {
    await reopened.close();
  }
  final merged = await PdfPageAssembly.merge(
      [PdfPageSelection(edited), PdfPageSelection(edited)]);
  final combined =
      await CraftPdfDocument.open(CraftPdfReader.fromBytes(merged));
  if (combined.pageTotal() != 2) throw StateError('Page assembly failed');
  await combined.close();
  await _checkCompatibility(edited);
  await _checkRecoveryAndFlatten(edited);
  await _checkSigning(edited);
  print(
      'DPDF $dpdfRuntime: codecs, creation, multifont editing, extraction, merge and RSA signing OK');
}

Future<void> _checkCompatibility(Uint8List input) async {
  final output = BytesBuilder();
  final document = CraftPdfDocument(
      reader: CraftPdfReader.fromBytes(input),
      writer: CraftPdfWriter.fromBytesBuilder(output),
      properties: CraftStampingProperties().useAppendMode());
  await document.load();
  final page = (await document.pageAt(1))!;
  final overlay = await PdfPageOverlay.create(page);
  overlay.beginText();
  await overlay.setFontAndSize(CraftPdfFontFactory.createFont('Helvetica'), 12);
  overlay.moveText(20, 40).showText('WEB OVERLAY').endText();
  (await document.documentDetails()).setTitle('Revisão 世界');
  await document.close();
  final bytes = output.takeBytes();
  final quick = await PdfQuickInfo.fromBytes(bytes);
  if (quick.pageCount != 1 || quick.hasDocMdp) {
    throw StateError('Quick inspection failed');
  }
  final reopened = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
  try {
    final title = await (await reopened.documentDetails())
        .pdfRepresentation()
        .stringEntry(CraftPdfName.title);
    if (title?.decodeMappingText() != 'Revisão 世界') {
      throw StateError(
          'Incremental metadata update was lost: ${title?.decodeMappingText()}');
    }
    final text = await PdfTextExtraction.fromPage((await reopened.pageAt(1))!);
    if (!text.contains('WEB OVERLAY')) {
      throw StateError('Incremental overlay was lost: $text');
    }
  } finally {
    await reopened.close();
  }
}

void _checkCodecs() {
  final pixels = Uint8List.fromList([0, 0, 0xff, 0x80, 0xaa, 0x80]);
  final fax = CraftCCITTG4Encoder.compress(pixels, 9, 3);
  final restored = Uint8List(pixels.length);
  CraftTIFFFaxDecoder(1, 9, 3).decodeT6(restored, fax, 0, 3, 0);
  if (base64.encode(restored) != base64.encode(pixels)) {
    throw StateError('G4 codec round trip failed');
  }
  final png = CraftPngWriter()
    ..writeHeader(2, 1, 8, 6)
    ..writeData(Uint8List.fromList([255, 0, 0, 128, 0, 255, 0, 255]), 8)
    ..writeEnd();
  final decoded = CraftImageDataFactory.create(png.toBytes());
  if (decoded.getWidth() != 2 ||
      base64.encode(decoded.imageMask!.getData()!) !=
          base64.encode([128, 255])) {
    throw StateError('PNG alpha separation failed');
  }
}

Future<void> _checkSigning(Uint8List input) async {
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
  final signer = CraftPdfSigner.fromBytesBuilder(input, output);
  await signer.signDetached(_LocalSignature(privateKey), [certificate]);
  final signed =
      await CraftPdfDocument.open(CraftPdfReader.fromBytes(output.takeBytes()));
  try {
    final signatures = CraftSignatureUtil(signed);
    final names = await signatures.getSignatureNames();
    if (names.length != 1) throw StateError('Missing PDF signature');
    final cms = await signatures.readSignatureData(names.single);
    if (cms == null || !cms.verify()) {
      throw StateError('RSA signature verification failed');
    }
  } finally {
    await signed.close();
  }
}

class _LocalSignature implements CraftExternalSignature {
  final RSAPrivateKey key;
  _LocalSignature(this.key);
  @override
  String getDigestAlgorithmName() => 'SHA-256';
  @override
  String getSignatureAlgorithmName() => 'RSA';
  @override
  CraftSignatureMechanismParams? getSignatureMechanismParameters() => null;
  @override
  Future<Uint8List> sign(Uint8List message) async {
    final signer = Signer('SHA-256/RSA')..init(true, PrivateKeyParameter(key));
    return signer.generateSignature(message).bytes;
  }
}

Future<void> _checkFormExtraction() async {
  final bytes = BytesBuilder();
  final doc = CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(bytes));
  final page = await doc.appendBlankPage();
  final fonts = CraftPdfDictionary()
    ..put(
        CraftPdfName('F1'),
        CraftPdfDictionary()
          ..put(CraftPdfName.type, CraftPdfName.font)
          ..put(CraftPdfName.subtype, CraftPdfName('Type1'))
          ..put(CraftPdfName.baseFont, CraftPdfName('Helvetica')));
  final form = CraftPdfStream.withBytes(
      Uint8List.fromList(ascii.encode('BT /F1 12 Tf (embedded) Tj ET')), 0)
    ..put(CraftPdfName.type, CraftPdfName('XObject'))
    ..put(CraftPdfName.subtype, CraftPdfName('Form'))
    ..put(CraftPdfName('BBox'), CraftPdfArray.fromInts([0, 0, 100, 100]))
    ..put(CraftPdfName.resources,
        CraftPdfDictionary()..put(CraftPdfName.font, fonts));
  page.pdfRepresentation()
    ..put(
        CraftPdfName.resources,
        CraftPdfDictionary()
          ..put(CraftPdfName('XObject'),
              CraftPdfDictionary()..put(CraftPdfName('Embedded'), form)))
    ..put(
        CraftPdfName.contents,
        CraftPdfStream.withBytes(
            Uint8List.fromList(ascii.encode(
                '/Embedded Do /Span << /ActualText <80A0> >> BDC /Embedded Do EMC')),
            0));
  await doc.close();
  final reopened =
      await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes.takeBytes()));
  try {
    final extracted =
        await PdfTextExtraction.fromPage((await reopened.pageAt(1))!);
    if (extracted != 'embedded•€') {
      throw StateError('Form text extraction failed: $extracted');
    }
  } finally {
    await reopened.close();
  }
}

Future<void> _checkRecoveryAndFlatten(Uint8List input) async {
  final broken = Uint8List.fromList(latin1.encode(latin1
      .decode(input)
      .replaceFirst(RegExp(r'startxref\s+\d+'), 'startxref\n99999999')));
  final options = CraftReaderProperties()
    ..recoveryMode = PdfRecoveryMode.skipStreams;
  final recovered = await CraftPdfDocument.open(
      CraftPdfReader.fromSource(PdfMemorySource(broken), options));
  if (!recovered.wasRepaired || recovered.pageTotal() != 1) {
    throw StateError('Optional recovery failed');
  }
  await recovered.close();
  final flattened = await PdfPageAssembly.merge(
      [PdfPageSelection(broken, readerProperties: options)],
      mode: PdfMergeMode.flatten);
  final reopened =
      await CraftPdfDocument.open(CraftPdfReader.fromBytes(flattened));
  if ((await PdfTextExtraction.fromPage((await reopened.pageAt(1))!)).isEmpty) {
    throw StateError('Flatten lost page content');
  }
  await reopened.close();
}
