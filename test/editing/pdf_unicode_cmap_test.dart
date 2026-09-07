import 'dart:typed_data';
import 'package:dpdf/src/editing/pdf_unicode_cmap.dart';
import 'package:test/test.dart';

PdfUnicodeCMap parse(String body) =>
    PdfUnicodeCMap.parse(Uint8List.fromList(body.codeUnits));
Uint8List bytes(List<int> values) => Uint8List.fromList(values);
const space = '1 begincodespacerange <00> <FF> endcodespacerange ';

void main() {
  test('bfchar supports supplementary scalars, ligatures and whitespace', () {
    final cmap = parse('''/CIDInit /ProcSet findresource begin
      /Registry (Ignored \\(beginbfchar\\)) def
      $space % operator in comment: usecmap
      3 beginbfchar <01> <00 E7> <02> <D83DDE00> <03> <00660069> endbfchar
      end''');
    expect(cmap.decode(bytes([1, 2, 3])), 'ç😀fi');
  });
  test('scalar and array bfrange destinations', () {
    final cmap = parse('${space}2 beginbfrange '
        '<20> <22> <0041> <30> <32> [<0061> <D840DC3E> <00660066>] endbfrange');
    expect(cmap.decode(bytes([32, 33, 34, 48, 49, 50])),
        'ABC a𠀾ff'.replaceAll(' ', ''));
  });
  test('variable width code spaces preserve code length', () {
    final cmap =
        parse('2 begincodespacerange <00> <7F> <8100> <81FF> endcodespacerange '
            '2 beginbfchar <41> <0041> <8141> <03B2> endbfchar');
    expect(cmap.decode(bytes([65, 129, 65])), 'Aβ');
    expect(() => cmap.decode(bytes([129])), throwsFormatException);
    expect(() => cmap.decode(bytes([66])), throwsFormatException);
  });
  test('code space checks each byte, not only integer interval', () {
    expect(
        () => parse('1 begincodespacerange <8140> <827E> endcodespacerange '
            '1 beginbfchar <8180> <0041> endbfchar'),
        throwsFormatException);
  });
  test('later explicit mapping overrides earlier mapping', () {
    final cmap =
        parse('${space}2 beginbfchar <01> <0041> <01> <0042> endbfchar');
    expect(cmap.decode(bytes([1])), 'B');
  });
  test('rejects malformed blocks, codes and Unicode', () {
    for (final body in [
      '${space}1 beginbfchar <01> <D800> endbfchar',
      '${space}1 beginbfchar <01> <DC00> endbfchar',
      '${space}1 beginbfchar <01> <D8000041> endbfchar',
      '${space}1 beginbfchar <01> <01> endbfchar',
      '${space}1 beginbfchar <0001> <0041> endbfchar',
      '${space}2 beginbfchar <01> <0041> endbfchar',
      '${space}1 beginbfrange <01> <03> [<0041>] endbfrange',
      '${space}1 beginbfrange <01> <02> <00FF> endbfrange',
      '${space}1 beginbfchar <01> <XX> endbfchar',
      '${space}1 beginbfchar <01> <0041',
      '2 begincodespacerange <00> <FF> <0000> <FFFF> endcodespacerange',
      '1 begincodespacerange <0000000000> <FFFFFFFFFF> endcodespacerange',
      '101 beginbfchar',
      '${space}endbfchar',
    ]) {
      expect(() => parse(body), throwsFormatException, reason: body);
    }
  });
  test('unsupported inherited and CID CMaps fail explicitly', () {
    expect(() => parse('$space /Identity-H usecmap'), throwsUnsupportedError);
    expect(() => parse('$space 1 begincidchar'), throwsUnsupportedError);
  });
  test('range expansion is bounded before allocating', () {
    expect(
        () => parse(
            '1 begincodespacerange <00000000> <FFFFFFFF> endcodespacerange '
            '1 beginbfrange <00000000> <FFFFFFFF> <0041> endbfrange'),
        throwsFormatException);
  });
}
