import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/src/commons/exceptions/dpdf_exception.dart';
import 'package:dpdf/src/io/font/font_program_factory.dart';
import 'package:dpdf/src/io/font/true_type_collection.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/io/font/woff_converter.dart';
import 'package:test/test.dart';

import 'woff2_converter_test.dart'
    show buildCollectionWoff2, outlinesOf, sfntTables;

// --- building a font collection -------------------------------------------

List<int> _uint16(int value) => [(value >> 8) & 0xff, value & 0xff];

int _round4(int value) => (value + 3) & ~3;

/// The sum of the uint32 units of [data] between [start] and [start] +
/// [length], which is the checksum an sfnt directory records.
int checksum(Uint8List data, int start, int length) {
  final view = ByteData.sublistView(data);
  var sum = 0;
  for (var at = start; at + 4 <= start + length; at += 4) {
    sum = (sum + view.getUint32(at)) & 0xffffffff;
  }
  return sum;
}

/// A `name` table carrying [names] as Windows (3, 1, 0x409) records, which
/// is the platform every modern font names itself on.
Uint8List buildNameTable(Map<int, String> names) {
  final ids = names.keys.toList()..sort();
  final storage = <int>[];
  final records = <int>[];
  for (final id in ids) {
    final text = <int>[];
    for (final unit in names[id]!.codeUnits) {
      text.addAll(_uint16(unit));
    }
    records.addAll([
      ..._uint16(3), // platformID
      ..._uint16(1), // encodingID
      ..._uint16(0x409), // languageID
      ..._uint16(id),
      ..._uint16(text.length),
      ..._uint16(storage.length),
    ]);
    storage.addAll(text);
  }
  return Uint8List.fromList([
    ..._uint16(0), // format 0
    ..._uint16(ids.length),
    ..._uint16(6 + ids.length * 12), // stringOffset
    ...records,
    ...storage,
  ]);
}

/// One font of a collection under construction: which table each of its tags
/// resolves to in the shared pool.
class CollectionFont {
  final int sfntVersion;
  final Map<String, String> tables;

  CollectionFont(this.tables, {this.sfntVersion = 0x00010000});
}

/// Assembles a `ttcf` file out of a pool of tables and the fonts that name
/// them.
///
/// [pool] maps a pool key to the bytes of a table; each font of [fonts] maps
/// its own tags to pool keys. Two fonts naming the same key share one table,
/// which is the whole point of the format.
Uint8List buildTtc(
  Map<String, Uint8List> pool,
  List<CollectionFont> fonts, {
  int majorVersion = 1,
  int minorVersion = 0,
  Uint8List? signature,
  bool writeDsigFields = false,
  int? numFontsOverride,
}) {
  final withDsig = majorVersion == 2 && (writeDsigFields || signature != null);
  var cursor = 12 + fonts.length * 4 + (withDsig ? 12 : 0);
  final directoryOffsets = <int>[];
  for (final font in fonts) {
    directoryOffsets.add(cursor);
    cursor += 12 + font.tables.length * 16;
  }
  // The table pool follows every directory, each table on a four-byte
  // boundary as the specification requires of top-level tables.
  final positions = <String, int>{};
  for (final key in pool.keys) {
    cursor = _round4(cursor);
    positions[key] = cursor;
    cursor += pool[key]!.length;
  }
  var dsigOffset = 0;
  if (signature != null) {
    cursor = _round4(cursor);
    dsigOffset = cursor;
    cursor += signature.length;
  }

  final file = Uint8List(_round4(cursor));
  final view = ByteData.sublistView(file);
  file.setRange(0, 4, 'ttcf'.codeUnits);
  view.setUint16(4, majorVersion);
  view.setUint16(6, minorVersion);
  view.setUint32(8, numFontsOverride ?? fonts.length);
  for (var index = 0; index < fonts.length; index++) {
    view.setUint32(12 + index * 4, directoryOffsets[index]);
  }
  if (withDsig) {
    final at = 12 + fonts.length * 4;
    view.setUint32(at, signature == null ? 0 : 0x44534947);
    view.setUint32(at + 4, signature?.length ?? 0);
    view.setUint32(at + 8, dsigOffset);
  }

  for (final key in pool.keys) {
    file.setRange(
        positions[key]!, positions[key]! + pool[key]!.length, pool[key]!);
  }
  if (signature != null) {
    file.setRange(dsigOffset, dsigOffset + signature.length, signature);
  }

  for (var index = 0; index < fonts.length; index++) {
    final font = fonts[index];
    final start = directoryOffsets[index];
    final tags = font.tables.keys.toList()..sort();
    view.setUint32(start, font.sfntVersion);
    view.setUint16(start + 4, tags.length);
    var entrySelector = 0;
    while (1 << (entrySelector + 1) <= tags.length) {
      entrySelector++;
    }
    final searchRange = (1 << entrySelector) * 16;
    view.setUint16(start + 6, searchRange);
    view.setUint16(start + 8, entrySelector);
    view.setUint16(start + 10, tags.length * 16 - searchRange);
    for (var slot = 0; slot < tags.length; slot++) {
      final record = start + 12 + slot * 16;
      final key = font.tables[tags[slot]]!;
      final offset = positions[key]!;
      final length = pool[key]!.length;
      file.setRange(record, record + 4, tags[slot].codeUnits);
      view.setUint32(record + 4, checksum(file, offset, _round4(length)));
      view.setUint32(record + 8, offset);
      view.setUint32(record + 12, length);
    }
  }
  return file;
}

void main() {
  final sfnt = File('test/assets/ABeeZee-Regular.ttf').readAsBytesSync();
  final tables = sfntTables(sfnt);

  const firstNames = {
    1: 'Collection Sample',
    2: 'First',
    4: 'Collection Sample First',
    6: 'CollectionSample-First',
  };
  const secondNames = {
    1: 'Collection Sample',
    2: 'Second',
    4: 'Collection Sample Second',
    6: 'CollectionSample-Second',
  };

  /// Two fonts of one collection: they share every table the format means to
  /// be shared -- `glyf` and `loca` above all -- carry a `name` table each,
  /// and carry two byte-identical but separate copies of OS/2, which is a
  /// table the specification says each font should own.
  Uint8List sampleCollection({
    int majorVersion = 1,
    Uint8List? signature,
    bool writeDsigFields = false,
    int? numFontsOverride,
  }) {
    final pool = <String, Uint8List>{};
    final shared = <String, String>{};
    for (final tag in tables.keys) {
      if (tag == 'name' || tag == 'OS/2') continue;
      pool[tag] = tables[tag]!;
      shared[tag] = tag;
    }
    pool['name#0'] = buildNameTable(firstNames);
    pool['name#1'] = buildNameTable(secondNames);
    pool['OS/2#0'] = tables['OS/2']!;
    pool['OS/2#1'] = Uint8List.fromList(tables['OS/2']!);
    return buildTtc(
      pool,
      [
        CollectionFont({...shared, 'name': 'name#0', 'OS/2': 'OS/2#0'}),
        CollectionFont({...shared, 'name': 'name#1', 'OS/2': 'OS/2#1'}),
      ],
      majorVersion: majorVersion,
      signature: signature,
      writeDsigFields: writeDsigFields,
      numFontsOverride: numFontsOverride,
    );
  }

  group('a TrueType collection header', () {
    test('is recognised by its tag alone', () {
      expect(TrueTypeCollection.isCollection(sampleCollection()), isTrue);
      expect(TrueTypeCollection.isCollection(sfnt), isFalse);
      expect(TrueTypeCollection.isCollection(const [0x74, 0x74]), isFalse);
    });

    test('reads version 1.0: the count and one offset per font', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      expect(collection.numFonts, 2);
      expect(collection.version, 0x00010000);
      expect(collection.majorVersion, 1);
      expect(collection.minorVersion, 0);
      expect(collection.directoryOffsets.length, 2);
      expect(collection.directoryOffsets[0], 20); // 12 + 2 * 4
      expect(collection.directoryOffsets[0],
          lessThan(collection.directoryOffsets[1]));
      expect(collection.hasDigitalSignature, isFalse);
      expect(collection.digitalSignature, isNull);
    });

    test('reads the three extra fields of version 2.0', () {
      final signature = Uint8List.fromList(List.generate(24, (i) => i + 1));
      final bytes = sampleCollection(majorVersion: 2, signature: signature);
      final collection = TrueTypeCollection.fromBytes(bytes);
      expect(collection.version, 0x00020000);
      // The first directory now starts past the DSIG fields.
      expect(collection.directoryOffsets[0], 32); // 12 + 2 * 4 + 12
      expect(collection.dsigTag, 0x44534947);
      expect(collection.dsigLength, 24);
      expect(collection.hasDigitalSignature, isTrue);
      expect(collection.digitalSignature, signature);
      expect(collection.numFonts, 2);
    });

    test('reads a version 2.0 header whose last three fields are null', () {
      final collection = TrueTypeCollection.fromBytes(
          sampleCollection(majorVersion: 2, writeDsigFields: true));
      expect(collection.version, 0x00020000);
      expect(collection.dsigTag, 0);
      expect(collection.dsigLength, 0);
      expect(collection.dsigOffset, 0);
      expect(collection.hasDigitalSignature, isFalse);
      expect(collection.digitalSignature, isNull);
      expect(collection.getFont(1), isA<TrueTypeFont>());
    });
  });

  group('listing a TrueType collection', () {
    test('names every font without loading one', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      final entries = collection.describeAll();
      expect(entries.length, 2);
      expect(entries[0].index, 0);
      expect(entries[0].postScriptName, 'CollectionSample-First');
      expect(entries[0].fullName, 'Collection Sample First');
      expect(entries[0].familyName, 'Collection Sample');
      expect(entries[0].subfamilyName, 'First');
      expect(entries[1].postScriptName, 'CollectionSample-Second');
      expect(entries[1].subfamilyName, 'Second');
      expect(entries[0].sfntVersion, 0x00010000);
      expect(entries[0].isCff, isFalse);
      expect(entries[0].tableTags, contains('glyf'));
      expect(entries[0].tableTags, contains('name'));
      expect(entries[0].directoryOffset, collection.directoryOffsets[0]);
    });

    test('finds a font by any of the names it answers to', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      expect(collection.indexOfName('CollectionSample-Second'), 1);
      expect(collection.indexOfName('collectionsample-second'), 1);
      expect(collection.indexOfName('Collection Sample First'), 0);
      expect(collection.indexOfName('Collection Sample'), 0);
      expect(collection.indexOfName('Collection Sample Second'), 1);
      expect(collection.indexOfName('Helvetica'), -1);
      expect(collection.indexOfName(''), -1);
      expect(
          identical(collection.getFontByName('CollectionSample-Second'),
              collection.getFont(1)),
          isTrue);
    });

    test('describes the same font once', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      expect(identical(collection.describe(0), collection.describe(0)), isTrue);
    });
  });

  group('opening the fonts of a TrueType collection', () {
    test('opens each font with its own name', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      final first = collection.getFont(0);
      final second = collection.getFont(1);
      expect(first.getFontNames().getFontName(), 'CollectionSample-First');
      expect(second.getFontNames().getFontName(), 'CollectionSample-Second');
      expect(first.getCollectionIndex(), 0);
      expect(second.getCollectionIndex(), 1);
      expect(second.getDirectoryOffset(), collection.directoryOffsets[1]);
    });

    test('reads the same metrics the single font file gives', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      final plain = TrueTypeFont.fromBytes(sfnt);
      for (final font in [collection.getFont(0), collection.getFont(1)]) {
        expect(font.getFontMetrics().getUnitsPerEm(),
            plain.getFontMetrics().getUnitsPerEm());
        expect(font.getFontMetrics().getNumberOfGlyphs(),
            plain.getFontMetrics().getNumberOfGlyphs());
        expect(
            font.getFontMetrics().getBbox(), plain.getFontMetrics().getBbox());
        for (final code in 'Aegj1'.codeUnits) {
          expect(
              font.getGlyph(code)!.getCode(), plain.getGlyph(code)!.getCode(),
              reason: 'glyph of ${String.fromCharCode(code)}');
          expect(font.getGlyph(code)!.getWidth(),
              plain.getGlyph(code)!.getWidth());
        }
      }
    });

    test('gives the same font object back instead of parsing twice', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      expect(identical(collection.getFont(1), collection.getFont(1)), isTrue);
    });
  });

  group('sharing tables across a collection', () {
    test('points both directories at one copy of the heavy tables', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      final shared = collection.sharedTables(0, 1);
      expect(shared, containsAll(['glyf', 'loca', 'hmtx', 'maxp', 'cmap']));
      // A table each font owns is not shared, even when the bytes happen to
      // be identical: the two copies lie at different offsets.
      expect(shared, isNot(contains('name')));
      expect(shared, isNot(contains('OS/2')));
      final first = collection.tableOffsets(0);
      final second = collection.tableOffsets(1);
      expect(second['glyf'], first['glyf']);
      expect(second['loca'], first['loca']);
      expect(second['name'], isNot(first['name']));
      expect(second['OS/2'], isNot(first['OS/2']));
    });

    test('reads a shared table in place, out of the one buffer', () {
      final bytes = sampleCollection();
      final collection = TrueTypeCollection.fromBytes(bytes);
      expect(identical(collection.bytes, bytes), isTrue);
      // Neither font was given a buffer of its own, so the shared glyf table
      // exists once in memory however many fonts name it.
      for (final font in [collection.getFont(0), collection.getFont(1)]) {
        expect(identical(font.fontParser.raf.getBytes(), bytes), isTrue);
        expect(font.fontParser.tables['glyf']![0],
            collection.tableOffsets(0)['glyf']);
      }
    });

    test('a collection is smaller than the two fonts apart', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      final apart =
          collection.extractSfnt(0).length + collection.extractSfnt(1).length;
      expect(collection.bytes.length, lessThan(apart));
    });
  });

  group('extracting one font of a collection', () {
    test('rebuilds it as a font file of its own', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      final extracted = collection.extractSfnt(1);
      final rebuilt = sfntTables(extracted);
      expect(rebuilt.keys.toSet(), collection.describe(1).tableTags.toSet());
      for (final tag in rebuilt.keys) {
        if (tag == 'head') continue; // checksumAdjustment is rewritten
        if (tag == 'name') {
          expect(rebuilt[tag], buildNameTable(secondNames));
          continue;
        }
        expect(rebuilt[tag], tables[tag], reason: 'table $tag');
      }
      // The outlines are the ones the original font file carries.
      expect(outlinesOf(extracted).map((o) => o.toString()).toList(),
          outlinesOf(sfnt).map((o) => o.toString()).toList());
      expect(TrueTypeFont.fromBytes(extracted).getFontNames().getFontName(),
          'CollectionSample-Second');
    });

    test('closes the checksum a standalone font has to close', () {
      final extracted =
          TrueTypeCollection.fromBytes(sampleCollection()).extractSfnt(0);
      // "Calculate the checksum for the entire font. Subtract that value from
      // 0xB1B0AFBA. Store the result in the 'head' table checksumAdjustment
      // field" -- so the sum of the finished file is that constant again.
      expect(checksum(extracted, 0, extracted.length), 0xb1b0afba);
      final head = sfntTables(extracted)['head']!;
      expect(ByteData.sublistView(head).getUint32(8), isNot(0));
    });

    test('subsets out of the shared tables', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      final font = collection.getFont(1);
      final glyphs = {
        for (final code in 'Aeg'.codeUnits) font.getGlyph(code)!.getCode()
      };
      final subset = font.getSubset(glyphs, true);
      // The subsetter reads glyf and loca where the collection keeps them,
      // and writes a font that stands on its own.
      expect(String.fromCharCodes(subset, 0, 4), isNot('ttcf'));
      expect(subset.length, lessThan(collection.extractSfnt(1).length));
      final shrunk = sfntTables(subset);
      expect(shrunk.keys, contains('glyf'));
      expect(shrunk['glyf']!.length, lessThan(tables['glyf']!.length));
    });

    test('is what the font offers as its embeddable program', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      final stream = collection.getFont(0).getFontStreamBytes()!;
      // Not the whole collection: a PDF font stream holds one font.
      expect(stream.length, lessThan(collection.bytes.length));
      expect(stream, collection.extractSfnt(0));
      expect(String.fromCharCodes(stream, 0, 4), isNot('ttcf'));
    });
  });

  group('the font program factory', () {
    test('opens a font of a collection by index', () {
      final bytes = sampleCollection();
      final font = FontProgramFactory.createFontFromCollection(bytes, index: 1)
          as TrueTypeFont;
      expect(font.getFontNames().getFontName(), 'CollectionSample-Second');
    });

    test('opens a font of a collection by name', () {
      final bytes = sampleCollection();
      final font = FontProgramFactory.createFontFromCollection(bytes,
          name: 'Collection Sample First') as TrueTypeFont;
      expect(font.getFontNames().getFontName(), 'CollectionSample-First');
    });

    test('takes the first font when raw bytes carry a collection', () {
      final font =
          FontProgramFactory.createFontFromBytes(sampleCollection(), false)
              as TrueTypeFont;
      expect(font.getFontNames().getFontName(), 'CollectionSample-First');
    });

    test('reads the index a path spells after the comma', () {
      final directory = Directory.systemTemp.createTempSync('dpdf_ttc');
      try {
        final path = '${directory.path}/sample.ttc';
        File(path).writeAsBytesSync(sampleCollection());
        final second =
            FontProgramFactory.createFont('$path,1', false) as TrueTypeFont;
        expect(second.getFontNames().getFontName(), 'CollectionSample-Second');
        final first =
            FontProgramFactory.createFont(path, false) as TrueTypeFont;
        expect(first.getFontNames().getFontName(), 'CollectionSample-First');
      } finally {
        directory.deleteSync(recursive: true);
      }
    });
  });

  group('a WOFF 2.0 collection end to end', () {
    test('rebuilds a collection whose second font opens', () {
      final rebuilt = WoffConverter.toSfnt(buildCollectionWoff2(sfnt, 2));
      expect(TrueTypeCollection.isCollection(rebuilt), isTrue);
      final collection = TrueTypeCollection.fromBytes(rebuilt);
      expect(collection.numFonts, 2);
      // The WOFF 2.0 collection this test builds lets both fonts share every
      // table, so nothing at all is duplicated.
      expect(collection.sharedTables(0, 1),
          collection.describe(0).tableTags.toSet());
      final second = collection.getFont(1);
      expect(second.getCollectionIndex(), 1);
      expect(outlinesOf(collection.extractSfnt(1)).map((o) => o.toString()),
          outlinesOf(sfnt).map((o) => o.toString()));
      final plain = TrueTypeFont.fromBytes(sfnt);
      for (final code in 'Aegj1'.codeUnits) {
        expect(
            second.getGlyph(code)!.getCode(), plain.getGlyph(code)!.getCode());
      }
    });

    test('reaches the same font through the factory', () {
      final font = FontProgramFactory.createFontFromCollection(
          buildCollectionWoff2(sfnt, 2),
          index: 1) as TrueTypeFont;
      expect(font.getCollectionIndex(), 1);
      expect(font.getFontMetrics().getNumberOfGlyphs(),
          TrueTypeFont.fromBytes(sfnt).getFontMetrics().getNumberOfGlyphs());
    });
  });

  group('a broken TrueType collection', () {
    test('is rejected when it holds no font at all', () {
      expect(
          () => TrueTypeCollection.fromBytes(
              sampleCollection(numFontsOverride: 0)),
          throwsA(isA<DpdfException>()));
    });

    test('is rejected when a directory offset leaves the file', () {
      final bytes = sampleCollection();
      final broken = Uint8List.fromList(bytes);
      ByteData.sublistView(broken).setUint32(16, bytes.length + 4096);
      expect(() => TrueTypeCollection.fromBytes(broken),
          throwsA(isA<DpdfException>()));
    });

    test('is rejected when a directory runs past the end of the file', () {
      final bytes = sampleCollection();
      final broken = Uint8List.fromList(bytes);
      // The second directory now claims more tables than the file can hold.
      final second = ByteData.sublistView(broken).getUint32(16);
      ByteData.sublistView(broken).setUint16(second + 4, 0xffff);
      expect(() => TrueTypeCollection.fromBytes(broken),
          throwsA(isA<DpdfException>()));
    });

    test('is rejected when a table record reaches past the end', () {
      final bytes = sampleCollection();
      final broken = Uint8List.fromList(bytes);
      final view = ByteData.sublistView(broken);
      final first = view.getUint32(12);
      view.setUint32(first + 12 + 12, bytes.length); // length of table 0
      expect(() => TrueTypeCollection.fromBytes(broken),
          throwsA(isA<DpdfException>()));
    });

    test('is rejected when the file stops inside the header', () {
      final bytes = sampleCollection();
      for (final cut in [4, 8, 11, 14]) {
        expect(() => TrueTypeCollection.fromBytes(bytes.sublist(0, cut)),
            throwsA(isA<DpdfException>()),
            reason: 'cut at $cut');
      }
    });

    test('is rejected when the file stops inside a table directory', () {
      final bytes = sampleCollection();
      final truncated = bytes.sublist(0, bytes.length ~/ 2);
      expect(() => TrueTypeCollection.fromBytes(truncated),
          throwsA(isA<DpdfException>()));
    });

    test('is rejected when the header version is not one this reader knows',
        () {
      final broken = Uint8List.fromList(sampleCollection());
      ByteData.sublistView(broken).setUint16(4, 3);
      expect(() => TrueTypeCollection.fromBytes(broken),
          throwsA(isA<DpdfException>()));
    });

    test('is rejected when it is not a collection at all', () {
      expect(() => TrueTypeCollection.fromBytes(sfnt),
          throwsA(isA<DpdfException>()));
    });

    test('refuses an index the collection does not hold', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      expect(() => collection.getFont(2), throwsA(isA<DpdfException>()));
      expect(() => collection.getFont(-1), throwsA(isA<DpdfException>()));
      expect(() => collection.describe(2), throwsA(isA<DpdfException>()));
      expect(() => collection.extractSfnt(7), throwsA(isA<DpdfException>()));
      expect(() => collection.tableOffsets(2), throwsA(isA<DpdfException>()));
      expect(
          () => collection.sharedTables(0, 2), throwsA(isA<DpdfException>()));
    });

    test('refuses a name the collection does not hold', () {
      final collection = TrueTypeCollection.fromBytes(sampleCollection());
      expect(() => collection.getFontByName('Times New Roman'),
          throwsA(isA<DpdfException>()));
    });
  });
}
