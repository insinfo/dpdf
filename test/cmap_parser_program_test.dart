import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/io/font/cmap/abstract_cmap.dart';
import 'package:dpdf/src/io/font/cmap/cmap_object.dart';
import 'package:dpdf/src/io/font/cmap/cmap_parser.dart';
import 'package:dpdf/src/io/font/cmap/cmap_location.dart';
import 'package:dpdf/src/io/source/pdf_tokenizer.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';

class _Map extends AbstractCMap {
  final entries = <String, String>{};
  @override
  void registerMappedCode(String mark, CMapObject code) {
    entries[mark] = code.toString();
  }
}

class _Input extends PdfTokenizer {
  bool closed = false;
  _Input(String text)
      : super(RandomAccessFileOrArray(Uint8List.fromList(ascii.encode(text))));
  @override
  void closeSync() {
    closed = true;
    super.closeSync();
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

class _Sources implements CMapLocation {
  final Map<String, String> programs;
  final opened = <_Input>[];
  _Sources(this.programs);
  @override
  _Input getLocationSync(String location) {
    final input = _Input(programs[location]!);
    opened.add(input);
    return input;
  }

  @override
  Future<_Input> getLocation(String location) async =>
      getLocationSync(location);
}

void main() {
  for (final sync in [true, false]) {
    Future<void> read(String name, _Map map, _Sources source) async {
      if (sync) {
        CMapParser.loadCidMappingsSync(name, map, source);
      } else {
        await CMapParser.loadCidMappings(name, map, source);
      }
    }

    test('CMap metadata and included mappings (${sync ? 'sync' : 'async'})',
        () async {
      final sources = _Sources({
        'root':
            '/CMapName /OwnMap def /Registry (Local) def /Ordering (Custom) def /Supplement 2 def /base usecmap 1 begincidchar <42> 12 endcidchar',
        'base':
            '/CMapName /BaseMap def 1 begincidrange <30> <32> 7 endcidrange',
      });
      final map = _Map();
      await read('root', map, sources);
      expect(map.getName(), 'OwnMap');
      expect(map.characterRegistry(), 'Local');
      expect(map.characterCollection(), 'Custom');
      expect(map.collectionSupplement(), 2);
      expect(map.entries, {'0': '7', '1': '8', '2': '9', 'B': '12'});
      expect(sources.opened.every((input) => input.closed), isTrue);
    });
    test(
        'CMap rejects malformed programs and closes input (${sync ? 'sync' : 'async'})',
        () async {
      for (final program in [
        '1 begincidchar <41> endcidchar',
        '1 begincidchar <41> 3',
        '/Supplement (wrong) def',
        '<41> 3 endcidchar',
        '1 begincodespacerange <ff> <00> endcodespacerange',
        '1 beginbfchar <41> [<0041> endbfchar',
      ]) {
        final sources = _Sources({'root': program});
        await expectLater(read('root', _Map(), sources), throwsFormatException);
        expect(sources.opened.every((input) => input.closed), isTrue);
      }
    });
    test(
        'CMap inclusion cycles fail without leaked inputs (${sync ? 'sync' : 'async'})',
        () async {
      final sources =
          _Sources({'root': '/base usecmap', 'base': '/root usecmap'});
      await expectLater(
          read('root', _Map(), sources),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'diagnostic', contains('cycle'))));
      expect(sources.opened.length, 2);
      expect(sources.opened.every((input) => input.closed), isTrue);
    });
    test('CMap inclusion limit is explicit (${sync ? 'sync' : 'async'})',
        () async {
      final sources =
          _Sources({for (var n = 0; n <= 10; n++) '$n': '/${n + 1} usecmap'});
      await expectLater(
          read('0', _Map(), sources),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'diagnostic', contains('exceeds 10'))));
      expect(sources.opened.length, 10);
      expect(sources.opened.every((input) => input.closed), isTrue);
    });
  }
}
