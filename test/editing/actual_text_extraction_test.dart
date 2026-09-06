import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pdfcraft/src/editing/pdf_text_extraction.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_dictionary.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_name.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_string.dart';
import 'form_text_extraction_test.dart' as fixtures;

String extract(String content) =>
    PdfTextExtraction.fromContent(Uint8List.fromList(latin1.encode(content)),
        decoder: (_, bytes) => latin1.decode(bytes));
void main() {
  test('ActualText replaces multiple shows and line breaks once', () {
    expect(
        extract(
            'BT /F1 12 Tf (before) Tj /Span << /ActualText (readable) >> BDC (secret) Tj T* [(hidden) 10] TJ EMC (after) Tj ET'),
        'beforereadableafter');
  });
  test('Outer replacement wins over nested replacements', () {
    expect(
        extract(
            '/Span << /ActualText (outer) >> BDC /Span << /ActualText (inner) >> BDC BT /F1 12 Tf (secret) Tj ET EMC EMC'),
        'outer');
    expect(extract('/Span BMC /Span << /ActualText (inner) >> BDC EMC EMC'),
        'inner');
  });
  test('Empty replacement suppresses original text', () {
    expect(
        extract(
            '/Span << /ActualText () >> BDC BT /F1 12 Tf (secret) Tj ET EMC'),
        '');
  });
  test('PDFDocEncoding and UTF16 replacement text', () {
    expect(extract('/Span << /ActualText <80A0> >> BDC EMC'), '\u2022\u20ac');
    expect(
        extract('/Span << /ActualText <FEFF0041D83DDE00> >> BDC EMC'), 'A😀');
  });
  test('Unbalanced marking and malformed properties fail', () {
    for (final content in [
      'EMC',
      '/Span BMC',
      '/Span 4 BDC EMC',
      '/Span << /ActualText /Name >> BDC EMC',
      '/Span << /ActualText <FEFF00> >> BDC EMC',
      '/Span << /ActualText <FEFFD800> >> BDC EMC'
    ]) {
      expect(() => extract(content), throwsFormatException, reason: content);
    }
    expect(() => extract('/Span /P BDC EMC'), throwsUnsupportedError);
  });
  test('Marking without ActualText preserves text and accepts metadata', () {
    expect(
        extract(
            '/Span << /MCID 1 /Other true /Null null >> BDC BT /F1 12 Tf (visible) Tj ET EMC'),
        'visible');
  });
  test('Replacement does not conceal malformed text state', () {
    expect(() => extract('/Span << /ActualText (safe) >> BDC (bad) Tj EMC'),
        throwsFormatException);
  });
  test('Page resolves property resource dictionary', () async {
    final resources = fixtures.resources({})
      ..put(
          CraftPdfName('Properties'),
          CraftPdfDictionary()
            ..put(
                CraftPdfName('P'),
                CraftPdfDictionary()
                  ..put(CraftPdfName('ActualText'),
                      CraftPdfString('replacement'))));
    expect(
        await fixtures.extract(
            '/Span /P BDC BT /F1 12 Tf (secret) Tj ET EMC', resources),
        'replacement');
  });
  test('Replacement suppresses Form text but validates Form structure',
      () async {
    final resources =
        fixtures.resources({'X': fixtures.form('BT /F1 12 Tf (secret) Tj ET')});
    expect(
        await fixtures.extract(
            '/Span << /ActualText (replacement) >> BDC /X Do EMC /X Do',
            resources),
        'replacementsecret');
    final broken = fixtures.resources({'X': fixtures.form('BT BT')});
    await expectLater(
        fixtures.extract(
            '/Span << /ActualText (replacement) >> BDC /X Do EMC', broken),
        throwsFormatException);
  });
}
