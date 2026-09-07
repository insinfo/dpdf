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
  if (PdfDate.decode("D:20260827143000-03'00'") !=
      DateTime.utc(2026, 8, 27, 17, 30)) {
    throw StateError('PDF date lost its declared UTC offset');
  }
  final marker = Uint8List(2048)..setRange(0, 9, ascii.encode('startxref'));
  if (PdfTokenizer(RandomAccessFileOrArray(marker)).getStartxref() != 0) {
    throw StateError('Reverse marker search skipped the first bytes');
  }
  _checkCodecs();
  final text = PdfEncodings.convertToString(
      Uint8List.fromList([0x80, 0xa0]), PdfEncodings.PDF_DOC_ENCODING);
  if (text != '•€') throw StateError('PDFDocEncoding conversion failed');
  await _checkFormExtraction();
  final word = RandomAccessFileOrArray(
          Uint8List.fromList([127, 255, 255, 255, 255, 255, 255, 255]))
      .readBigInt64();
  if (word != (BigInt.one << 63) - BigInt.one) {
    throw StateError('64-bit platform backend lost precision');
  }
  final buffer = BytesBuilder();
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(buffer));
  final page = await document.appendBlankPage();
  final font = PdfDictionary()
    ..put(PdfName.type, PdfName.font)
    ..put(PdfName.subtype, PdfName('Type1'))
    ..put(PdfName.baseFont, PdfName('Helvetica'))
    ..put(PdfName.encoding, PdfName('WinAnsiEncoding'));
  final alternate = PdfDictionary()
    ..put(PdfName.type, PdfName.font)
    ..put(PdfName.subtype, PdfName('Type1'))
    ..put(PdfName.baseFont, PdfName('Courier'))
    ..put(PdfName.encoding, PdfName('WinAnsiEncoding'));
  page.pdfRepresentation().put(
      PdfName.resources,
      PdfDictionary()
        ..put(
            PdfName.font,
            PdfDictionary()
              ..put(PdfName('F1'), font)
              ..put(PdfName('Alternate'), alternate)));
  page.pdfRepresentation().put(
      PdfName.contents,
      PdfStream.withBytes(
          Uint8List.fromList(ascii.encode(
              'BT /F1 18 Tf 50 750 Td (Cliente: Pe) Tj /Alternate 18 Tf (dro. Total: 100.) Tj ET')),
          0));
  // This fixture has no metadata by design. Do not strip metadata from an
  // arbitrary input document to circumvent the editing API's validation.
  (await document.documentDetails()).pdfRepresentation().clear();
  await document.close();

  final edited = await PdfTextEditing.replace(
      buffer.takeBytes(), [const PdfTextReplacement(1, 'Pedro', 'João')]);
  final reopened = await PdfDocument.open(PdfReader.fromBytes(edited));
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
  final combined = await PdfDocument.open(PdfReader.fromBytes(merged));
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
  final document = PdfDocument(
      reader: PdfReader.fromBytes(input),
      writer: PdfWriter.fromBytesBuilder(output),
      properties: StampingProperties().useAppendMode());
  await document.load();
  final page = (await document.pageAt(1))!;
  final overlay = await PdfPageOverlay.create(page);
  overlay.beginText();
  await overlay.setFontAndSize(PdfFontFactory.createFont('Helvetica'), 12);
  overlay.moveText(20, 40).showText('WEB OVERLAY').endText();
  (await document.documentDetails()).setTitle('Revisão 世界');
  await document.close();
  final bytes = output.takeBytes();
  final quick = await PdfQuickInfo.fromBytes(bytes);
  if (quick.pageCount != 1 || quick.hasDocMdp) {
    throw StateError('Quick inspection failed');
  }
  final reopened = await PdfDocument.open(PdfReader.fromBytes(bytes));
  try {
    final title = await (await reopened.documentDetails())
        .pdfRepresentation()
        .stringEntry(PdfName.title);
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
  final fax = CCITTG4Encoder.compress(pixels, 9, 3);
  final restored = Uint8List(pixels.length);
  TIFFFaxDecoder(1, 9, 3).decodeT6(restored, fax, 0, 3, 0);
  if (base64.encode(restored) != base64.encode(pixels)) {
    throw StateError('G4 codec round trip failed');
  }
  final png = PngWriter()
    ..writeHeader(2, 1, 8, 6)
    ..writeData(Uint8List.fromList([255, 0, 0, 128, 0, 255, 0, 255]), 8)
    ..writeEnd();
  final decoded = ImageDataFactory.create(png.toBytes());
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
  final signer = PdfSigner.fromBytesBuilder(input, output);
  await signer.signDetached(_LocalSignature(privateKey), [certificate]);
  final signed =
      await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
  try {
    final signatures = SignatureUtil(signed);
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

Future<void> _checkFormExtraction() async {
  final bytes = BytesBuilder();
  final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
  final page = await doc.appendBlankPage();
  final fonts = PdfDictionary()
    ..put(
        PdfName('F1'),
        PdfDictionary()
          ..put(PdfName.type, PdfName.font)
          ..put(PdfName.subtype, PdfName('Type1'))
          ..put(PdfName.baseFont, PdfName('Helvetica')));
  final form = PdfStream.withBytes(
      Uint8List.fromList(ascii.encode('BT /F1 12 Tf (embedded) Tj ET')), 0)
    ..put(PdfName.type, PdfName('XObject'))
    ..put(PdfName.subtype, PdfName('Form'))
    ..put(PdfName('BBox'), PdfArray.fromInts([0, 0, 100, 100]))
    ..put(PdfName.resources, PdfDictionary()..put(PdfName.font, fonts));
  page.pdfRepresentation()
    ..put(
        PdfName.resources,
        PdfDictionary()
          ..put(PdfName('XObject'),
              PdfDictionary()..put(PdfName('Embedded'), form)))
    ..put(
        PdfName.contents,
        PdfStream.withBytes(
            Uint8List.fromList(ascii.encode(
                '/Embedded Do /Span << /ActualText <80A0> >> BDC /Embedded Do EMC')),
            0));
  await doc.close();
  final reopened =
      await PdfDocument.open(PdfReader.fromBytes(bytes.takeBytes()));
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
  final options = ReaderProperties()
    ..recoveryMode = PdfRecoveryMode.skipStreams;
  final recovered = await PdfDocument.open(
      PdfReader.fromSource(PdfMemorySource(broken), options));
  if (!recovered.wasRepaired || recovered.pageTotal() != 1) {
    throw StateError('Optional recovery failed');
  }
  await recovered.close();
  final flattened = await PdfPageAssembly.merge(
      [PdfPageSelection(broken, readerProperties: options)],
      mode: PdfMergeMode.flatten);
  final reopened = await PdfDocument.open(PdfReader.fromBytes(flattened));
  if ((await PdfTextExtraction.fromPage((await reopened.pageAt(1))!)).isEmpty) {
    throw StateError('Flatten lost page content');
  }
  await reopened.close();
}
