import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pdfcraft/src/compatibility/pdf_quick_info.dart';

void main() {
  test('header-only reads version and offset without claiming a document',
      () async {
    final info = await PdfQuickInfo.fromBytes(
        Uint8List.fromList(ascii.encode('xx%PDF-1.7\n')),
        readDocument: false);
    expect(info.versionString, '1.7');
    expect(info.versionOffset, 2);
    expect(info.versionRawHeader, '%PDF-1.7');
    expect(info.isPdf15OrAbove, isTrue);
    expect(info.pageCount, isNull);
    expect(info.isEncrypted, isNull);
  });
  test('version ordering and missing header', () async {
    for (final (header, expected) in [
      ('1.4', false),
      ('1.5', true),
      ('2.0', true)
    ]) {
      final info = await PdfQuickInfo.fromBytes(
          Uint8List.fromList(ascii.encode('%PDF-$header\n')),
          readDocument: false);
      expect(info.isPdf15OrAbove, expected);
    }
    final missing = await PdfQuickInfo.fromBytes(Uint8List.fromList([1, 2, 3]),
        readDocument: false);
    expect(missing.versionMajor, isNull);
    expect(missing.versionString, isNull);
  });
  test('reads declared DocMDP and may skip its inspection', () async {
    final bytes = await File(
            'test/compatibility/assets/generated_doc_mdp_allow_signatures.pdf')
        .readAsBytes();
    final info = await PdfQuickInfo.fromBytes(bytes);
    expect(info.pageCount, 1);
    expect(info.isEncrypted, isFalse);
    expect(info.hasDocMdp, isTrue);
    expect(info.docMdpPermissionP, 2);
    final skipped = await PdfQuickInfo.fromBytes(bytes, readMDPInfo: false);
    expect(skipped.hasDocMdp, isFalse);
    expect(skipped.docMdpPermissionP, isNull);
    expect(skipped.pageCount, 1);
  });
  test('plain document has no certification declaration', () async {
    final info = await PdfQuickInfo.fromBytes(
        await File('test/compatibility/assets/generated_three_pages.pdf')
            .readAsBytes());
    expect(info.pageCount, 3);
    expect(info.hasDocMdp, isFalse);
  });
}
