import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/io/font/cmap/cmap_location.dart';
import 'package:dpdf/src/io/font/cmap_encoding.dart';
import 'package:dpdf/src/io/source/pdf_tokenizer.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'package:dpdf/src/kernel/font/cid_unicode_repository.dart';
import 'package:dpdf/src/kernel/font/cid_unicode_table.dart';
import 'package:dpdf/src/kernel/font/unicode_code_map.dart';
import 'package:dpdf/src/kernel/font/pdf_type0_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';

Uint8List bytes(String value) => Uint8List.fromList(ascii.encode(value));
const program = '''begincmap
1 begincodespacerange <0000> <FFFF> endcodespacerange
3 beginbfchar <0001> <D83DDE00> <0002> <00660069> <0000> <0041> endbfchar
1 beginbfrange <0003> <0004> <4E00> endbfrange
endcmap''';

class Sources implements CraftCMapLocation {
  final Map<String, String> programs;
  int reads = 0;
  Completer<void>? gate;
  Sources(this.programs);
  @override
  Future<CraftPdfTokenizer> getLocation(String location) async {
    await gate?.future;
    return getLocationSync(location);
  }

  @override
  CraftPdfTokenizer getLocationSync(String location) {
    reads++;
    final value = programs[location];
    if (value == null) throw StateError('Missing fixture $location');
    return CraftPdfTokenizer(CraftRandomAccessFileOrArray(bytes(value)));
  }
}

void main() {
  test('CID table parses bfchar and ranges as full Unicode strings', () async {
    final source = Sources({'custom': program});
    final sync = CidUnicodeTable.readSync('custom', source);
    final async = await CidUnicodeTable.read('custom', source);
    for (final table in [sync, async]) {
      expect(table.textForCid(0), 'A');
      expect(table.textForCid(1), '😀');
      expect(table.scalarForCid(1), 0x1f600);
      expect(table.textForCid(2), 'fi');
      expect(table.scalarForCid(2), isNull);
      expect(table.textForCid(3), '一');
      expect(table.textForCid(4), '丁');
      expect(table.textForCid(9), '');
    }
  });
  test('CID table captures immutable validated values', () {
    final values = {1: 'original'};
    final table = CidUnicodeTable.fromMappings(values);
    values[1] = 'changed';
    expect(table.textForCid(1), 'original');
    expect(() => CidUnicodeTable.fromMappings({1: String.fromCharCode(0xd800)}),
        throwsFormatException);
  });
  test(
      'Repository combines simultaneous requests and shares completed sync reads',
      () async {
    final source = Sources({'Adobe-Japan1-UCS2': program})
      ..gate = Completer<void>();
    final repository = CidUnicodeRepository(location: source);
    final first = repository.loadCollection('Adobe', 'Japan1');
    final second = repository.loadCollection('Adobe', 'Japan1');
    expect(identical(first, second), isTrue);
    source.gate!.complete();
    final table = await first;
    expect(identical(table, await second), isTrue);
    expect(identical(table, repository.loadCollectionSync('Adobe', 'Japan1')),
        isTrue);
    expect(source.reads, 1);
  });
  test('Cache clear prevents pending requests from restoring stale values',
      () async {
    final source = Sources({'Adobe-Japan1-UCS2': program})
      ..gate = Completer<void>();
    final repository = CidUnicodeRepository(location: source);
    final pending = repository.loadCollection('Adobe', 'Japan1');
    repository.discardCachedCollections();
    source.gate!.complete();
    final old = await pending;
    final current = await repository.loadCollection('Adobe', 'Japan1');
    expect(identical(old, current), isFalse);
    expect(source.reads, 2);
  });
  test('Unsupported collections avoid I/O; missing sources can be retried',
      () async {
    final source = Sources({});
    final repository = CidUnicodeRepository(location: source);
    expect(await repository.loadCollection('Other', 'Japan1'), isNull);
    expect(repository.loadCollectionSync('Adobe', '../Japan1'), isNull);
    expect(source.reads, 0);
    await expectLater(
        repository.loadCollection('Adobe', 'Japan1'), throwsStateError);
    source.programs['Adobe-Japan1-UCS2'] = program;
    expect((await repository.loadCollection('Adobe', 'Japan1'))!.textForCid(1),
        '😀');
    expect(source.reads, 2);
  });
  test(
      'Unicode reverse lookup distinguishes source zero and supplementary scalar',
      () {
    final map = UnicodeCodeMap()
      ..setScalar(0, 0x1f600)
      ..setMapping(1, 'fi');
    expect(map.codeForScalar(0x1f600), 0);
    expect(map.codeForText('missing'), isNull);
    expect(map.hasSequence(0), isFalse);
    expect(map.hasSequence(1), isTrue);
  });
  test('Unicode CMap rejects odd byte strings and invalid surrogate values',
      () {
    for (final payload in ['<00>', '<DC00>', '<D8000041>', '(A)']) {
      expect(
          () => UnicodeCodeMap.fromBytes(
              bytes('1 beginbfchar <01> $payload endbfchar')),
          throwsFormatException);
    }
  });
  test('Composite font resolves indirect encoding and Unicode streams',
      () async {
    final document = await CraftPdfDocument.create(
        CraftPdfWriter.fromBytesBuilder(BytesBuilder()));
    final encoding = CraftPdfStream.withBytes(
        bytes(
            '1 begincodespacerange <00> <FF> endcodespacerange 1 begincidchar <01> 9 endcidchar'),
        0)
      ..attachToDocument(document);
    final unicode = CraftPdfStream.withBytes(
        bytes('1 beginbfchar <01> <0041> endbfchar'), 0)
      ..attachToDocument(document);
    final dictionary = CraftPdfDictionary()
      ..put(CraftPdfName.encoding, encoding.indirectHandle()!)
      ..put(CraftPdfName.toUnicode, unicode.indirectHandle()!);
    final font = CraftPdfType0Font.fromDictionary(dictionary);
    await font.initFromDictionary(dictionary);
    expect(font.decode(CraftPdfString.fromBytes(Uint8List.fromList([1]))), 'A');
  });
  test('Composite font uses original character bytes for ToUnicode', () {
    final font = CraftPdfType0Font.fromDictionary(CraftPdfDictionary())
      ..cmapEncoding = CraftCMapEncoding.fromBytes('fixture', bytes('''
1 begincodespacerange <00> <FF> endcodespacerange
1 begincidchar <01> 9 endcidchar'''))
      ..toUnicode = (UnicodeCodeMap()
        ..setMapping(1, 'source')
        ..setMapping(9, 'wrong'));
    expect(font.decode(CraftPdfString.fromBytes(Uint8List.fromList([1]))),
        'source');
  });
  test(
      'Composite font keeps CID replacement sequences and rejects truncated codes',
      () {
    final font = CraftPdfType0Font.fromDictionary(CraftPdfDictionary())
      ..cmapEncoding = CraftCMapEncoding('Identity-H')
      ..cid2unicode = CidUnicodeTable.fromMappings({1: '😀fi'});
    expect(font.decode(CraftPdfString.fromBytes(Uint8List.fromList([0, 1]))),
        '😀fi');
    expect(() => font.decode(CraftPdfString.fromBytes(Uint8List.fromList([0]))),
        throwsFormatException);
  });
}
