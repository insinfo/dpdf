import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/src/commons/exceptions/dpdf_exception.dart';
import 'package:dpdf/src/io/font/font_program_factory.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/io/font/woff2_converter.dart';
import 'package:dpdf/src/io/font/woff_converter.dart';
import 'package:test/test.dart';

// --- reading an sfnt font -------------------------------------------------

/// The tables of an sfnt font, by tag.
Map<String, Uint8List> sfntTables(Uint8List font) {
  final view = ByteData.sublistView(font);
  final count = view.getUint16(4);
  final tables = <String, Uint8List>{};
  for (var index = 0; index < count; index++) {
    final entry = 12 + index * 16;
    final tag = String.fromCharCodes(font, entry, entry + 4);
    final offset = view.getUint32(entry + 8);
    final length = view.getUint32(entry + 12);
    tables[tag] = Uint8List.sublistView(font, offset, offset + length);
  }
  return tables;
}

/// One glyph as the `glyf` table describes it, reduced to what a lossless
/// round trip has to preserve: the contours, every point with its on-curve
/// flag, the bounding box, and -- for a composite -- its component records.
class Outline {
  final int contours;
  final List<int> bbox;
  final List<int> endPoints;
  final List<int> xs;
  final List<int> ys;
  final List<bool> onCurve;
  final List<int> components;
  final List<int> instructions;

  Outline(this.contours, this.bbox, this.endPoints, this.xs, this.ys,
      this.onCurve, this.components, this.instructions);

  static final Outline empty = Outline(
      0, const [], const [], const [], const [], const [], const [], const []);

  @override
  String toString() => contours < 0
      ? 'composite(bbox: $bbox, components: ${components.length} bytes)'
      : 'simple($contours contours, ends: $endPoints, points: '
          '${List.generate(xs.length, (i) => '(${xs[i]},${ys[i]},'
              '${onCurve[i] ? 'on' : 'off'})')}, bbox: $bbox)';
}

/// Reads the outline of every glyph of a TrueType font.
List<Outline> outlinesOf(Uint8List font) {
  final tables = sfntTables(font);
  final head = ByteData.sublistView(tables['head']!);
  final maxp = ByteData.sublistView(tables['maxp']!);
  final numGlyphs = maxp.getUint16(4);
  final wide = head.getInt16(50) != 0;
  final loca = ByteData.sublistView(tables['loca']!);
  final glyf = tables['glyf']!;
  int offsetAt(int index) =>
      wide ? loca.getUint32(index * 4) : loca.getUint16(index * 2) * 2;

  final outlines = <Outline>[];
  for (var glyph = 0; glyph < numGlyphs; glyph++) {
    final start = offsetAt(glyph);
    final end = offsetAt(glyph + 1);
    if (start == end) {
      outlines.add(Outline.empty);
      continue;
    }
    outlines.add(readOutline(Uint8List.sublistView(glyf, start, end)));
  }
  return outlines;
}

Outline readOutline(Uint8List data) {
  final view = ByteData.sublistView(data);
  final contours = view.getInt16(0);
  final bbox = [
    view.getInt16(2),
    view.getInt16(4),
    view.getInt16(6),
    view.getInt16(8),
  ];
  if (contours < 0) {
    return Outline(contours, bbox, const [], const [], const [], const [],
        data.sublist(10), const []);
  }
  final endPoints = <int>[];
  for (var contour = 0; contour < contours; contour++) {
    endPoints.add(view.getUint16(10 + contour * 2));
  }
  var cursor = 10 + contours * 2;
  final instructionLength = view.getUint16(cursor);
  cursor += 2;
  final instructions = data.sublist(cursor, cursor + instructionLength);
  cursor += instructionLength;

  final total = endPoints.isEmpty ? 0 : endPoints.last + 1;
  final flags = <int>[];
  while (flags.length < total) {
    final flag = data[cursor++];
    flags.add(flag);
    if ((flag & 0x08) != 0) {
      final repeat = data[cursor++];
      for (var copy = 0; copy < repeat; copy++) {
        flags.add(flag);
      }
    }
  }
  final xs = <int>[];
  var x = 0;
  for (final flag in flags) {
    if ((flag & 0x02) != 0) {
      final delta = data[cursor++];
      x += (flag & 0x10) != 0 ? delta : -delta;
    } else if ((flag & 0x10) == 0) {
      x += view.getInt16(cursor);
      cursor += 2;
    }
    xs.add(x);
  }
  final ys = <int>[];
  var y = 0;
  for (final flag in flags) {
    if ((flag & 0x04) != 0) {
      final delta = data[cursor++];
      y += (flag & 0x20) != 0 ? delta : -delta;
    } else if ((flag & 0x20) == 0) {
      y += view.getInt16(cursor);
      cursor += 2;
    }
    ys.add(y);
  }
  return Outline(contours, bbox, endPoints, xs, ys,
      flags.map((flag) => (flag & 0x01) != 0).toList(), const [], instructions);
}

/// The advance width and left side bearing of every glyph.
List<List<int>> metricsOf(Uint8List font) {
  final tables = sfntTables(font);
  final numGlyphs = ByteData.sublistView(tables['maxp']!).getUint16(4);
  final numHMetrics = ByteData.sublistView(tables['hhea']!).getUint16(34);
  final hmtx = ByteData.sublistView(tables['hmtx']!);
  final metrics = <List<int>>[];
  var advance = 0;
  for (var glyph = 0; glyph < numGlyphs; glyph++) {
    final int bearing;
    if (glyph < numHMetrics) {
      advance = hmtx.getUint16(glyph * 4);
      bearing = hmtx.getInt16(glyph * 4 + 2);
    } else {
      bearing = hmtx.getInt16(numHMetrics * 4 + (glyph - numHMetrics) * 2);
    }
    metrics.add([advance, bearing]);
  }
  return metrics;
}

// --- writing a WOFF 2.0 file ----------------------------------------------

/// Writes bits least significant first, which is the order Brotli reads them.
class BitWriter {
  final List<int> bytes = <int>[];
  int _current = 0;
  int _used = 0;

  void write(int value, int count) {
    for (var bit = 0; bit < count; bit++) {
      _current |= ((value >> bit) & 1) << _used;
      if (++_used == 8) {
        bytes.add(_current);
        _current = 0;
        _used = 0;
      }
    }
  }

  void align() {
    if (_used != 0) {
      bytes.add(_current);
      _current = 0;
      _used = 0;
    }
  }
}

/// A Brotli stream that stores [data] rather than compressing it.
///
/// RFC 7932 allows an uncompressed meta-block, which is all these fixtures
/// need: the point of the exercise is the WOFF 2.0 structure around the
/// stream, not the stream itself, and this package ships no Brotli encoder.
Uint8List storedBrotli(List<int> data) {
  final writer = BitWriter();
  writer.write(0, 1); // WBITS = 16
  var offset = 0;
  do {
    final size = data.length - offset < 65536 ? data.length - offset : 65536;
    writer.write(0, 1); // ISLAST
    writer.write(0, 2); // MNIBBLES: four nibbles of MLEN
    writer.write(size - 1, 16);
    writer.write(1, 1); // ISUNCOMPRESSED
    writer.align();
    writer.bytes.addAll(data.sublist(offset, offset + size));
    offset += size;
  } while (offset < data.length);
  writer.write(1, 1); // ISLAST
  writer.write(1, 1); // ISLASTEMPTY
  writer.align();
  return Uint8List.fromList(writer.bytes);
}

/// The 63 tags a WOFF 2.0 directory entry can name by index, section 4.1.
const String knownTagText =
    'cmapheadhheahmtxmaxpnameOS/2postcvt fpgmglyflocaprepCFF VORGEBDT'
    'EBLCgasphdmxkernLTSHPCLTVDMXvheavmtxBASEGDEFGPOSGSUBEBSCJSTFMATH'
    'CBDTCBLCCOLRCPALSVG sbixacntavarbdatblocbslncvarfdscfeatfmtxfvar'
    'gvarhstyjustlcarmortmorxopbdproptrakZapfSilfGlatGlocFeatSill';

int knownTagIndex(String tag) {
  final at = knownTagText.indexOf(tag);
  return at >= 0 && at % 4 == 0 ? at ~/ 4 : 63;
}

List<int> base128(int value) {
  var size = 1;
  for (var rest = value; rest >= 128; rest >>= 7) {
    size++;
  }
  return List.generate(size, (index) {
    final part = (value >> (7 * (size - index - 1))) & 0x7f;
    return index < size - 1 ? part | 0x80 : part;
  });
}

List<int> uint255(int value) {
  if (value < 253) return [value];
  if (value < 506) return [255, value - 253];
  if (value < 762) return [254, value - 506];
  return [253, (value >> 8) & 0xff, value & 0xff];
}

List<int> uint32(int value) => [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];

/// One table on its way into a WOFF 2.0 file.
class Woff2Entry {
  final String tag;
  final Uint8List data;
  final int originalLength;
  final int version;

  Woff2Entry(this.tag, this.data, {int? originalLength, this.version = 0})
      : originalLength = originalLength ?? data.length;

  /// The version a table carries when nothing was done to it: glyf and loca
  /// number their null transformation 3, every other table numbers it 0.
  static Woff2Entry plain(String tag, Uint8List data) =>
      Woff2Entry(tag, data, version: tag == 'glyf' || tag == 'loca' ? 3 : 0);
}

/// Where the table [tag] sits in the sfnt font [font].
int tableOffset(Uint8List font, String tag) {
  final view = ByteData.sublistView(font);
  final count = view.getUint16(4);
  for (var index = 0; index < count; index++) {
    final entry = 12 + index * 16;
    if (String.fromCharCodes(font, entry, entry + 4) == tag) {
      return view.getUint32(entry + 8);
    }
  }
  throw StateError('no $tag table');
}

/// Assembles a WOFF 2.0 file out of [entries], in that order.
Uint8List encodeWoff2(
  List<Woff2Entry> entries, {
  int flavor = 0x00010000,
  required int totalSfntSize,
  List<List<int>>? fonts,
  List<int>? fontFlavors,
  int collectionVersion = 0x00010000,
  Uint8List? metadata,
  Uint8List? privateData,
}) {
  final directory = <int>[];
  for (final entry in entries) {
    final index = knownTagIndex(entry.tag);
    directory.add(index | (entry.version << 6));
    if (index == 63) directory.addAll(entry.tag.codeUnits);
    directory.addAll(base128(entry.originalLength));
    final transformed = entry.tag == 'glyf' || entry.tag == 'loca'
        ? entry.version == 0
        : entry.version != 0;
    if (transformed) directory.addAll(base128(entry.data.length));
  }
  if (fonts != null) {
    directory.addAll(uint32(collectionVersion));
    directory.addAll(uint255(fonts.length));
    for (var font = 0; font < fonts.length; font++) {
      directory.addAll(uint255(fonts[font].length));
      directory.addAll(uint32(fontFlavors![font]));
      for (final index in fonts[font]) {
        directory.addAll(uint255(index));
      }
    }
  }

  final block = <int>[];
  for (final entry in entries) {
    block.addAll(entry.data);
  }
  final compressed = storedBrotli(block);
  final compressedOffset = 48 + directory.length;

  // Every block of the file begins on a four-byte boundary, and the file
  // ends on one too.
  final body = <int>[...compressed];
  void pad() {
    while ((compressedOffset + body.length) % 4 != 0) {
      body.add(0);
    }
  }

  pad();
  var metaOffset = 0;
  var metaLength = 0;
  var metaOrigLength = 0;
  if (metadata != null) {
    metaOffset = compressedOffset + body.length;
    final packed = storedBrotli(metadata);
    metaLength = packed.length;
    metaOrigLength = metadata.length;
    body.addAll(packed);
    pad();
  }
  var privOffset = 0;
  var privLength = 0;
  if (privateData != null) {
    privOffset = compressedOffset + body.length;
    privLength = privateData.length;
    body.addAll(privateData);
    pad();
  }

  final header = <int>[
    ...uint32(0x774f4632),
    ...uint32(flavor),
    ...uint32(compressedOffset + body.length),
    (entries.length >> 8) & 0xff, entries.length & 0xff,
    0, 0, // reserved
    ...uint32(totalSfntSize),
    ...uint32(compressed.length),
    0, 1, 0, 0, // majorVersion, minorVersion
    ...uint32(metaOffset),
    ...uint32(metaLength),
    ...uint32(metaOrigLength),
    ...uint32(privOffset),
    ...uint32(privLength),
  ];
  return Uint8List.fromList([...header, ...directory, ...body]);
}

int round4(int value) => (value + 3) & ~3;

/// Wraps an sfnt font as a WOFF 2.0 file with nothing transformed.
Uint8List buildPlainWoff2(Uint8List sfnt,
    {Uint8List? metadata, Uint8List? privateData}) {
  final tables = sfntTables(sfnt);
  final entries = <Woff2Entry>[];
  var size = 12 + tables.length * 16;
  for (final tag in tables.keys) {
    entries.add(Woff2Entry.plain(tag, tables[tag]!));
    size += round4(tables[tag]!.length);
  }
  return encodeWoff2(entries,
      totalSfntSize: size, metadata: metadata, privateData: privateData);
}

/// Wraps an sfnt font as a WOFF 2.0 collection of [count] fonts that all
/// share the same tables, which is what section 6 exists to allow.
Uint8List buildCollectionWoff2(Uint8List sfnt, int count) {
  final tables = sfntTables(sfnt);
  final entries = <Woff2Entry>[];
  var size = 12 + 4 * count; // TTCTag, Version, numFonts, OffsetTable[]
  for (final tag in tables.keys) {
    entries.add(Woff2Entry.plain(tag, tables[tag]!));
    size += round4(tables[tag]!.length);
  }
  size += count * (12 + tables.length * 16);
  // A font of a collection has to name loca in the entry right after glyf,
  // because the two are transformed, and so shared, as a pair.
  final glyf = entries.indexWhere((entry) => entry.tag == 'glyf');
  final loca = entries.indexWhere((entry) => entry.tag == 'loca');
  final moved = entries.removeAt(loca);
  entries.insert(glyf + 1, moved);
  final indices = List.generate(entries.length, (index) => index);
  return encodeWoff2(entries,
      flavor: 0x74746366,
      totalSfntSize: size,
      fonts: List.generate(count, (_) => indices),
      fontFlavors: List.filled(count, 0x00010000));
}

/// Wraps an sfnt font as a WOFF 2.0 file whose `hmtx` has been transformed:
/// the left side bearings of the glyphs that have their own advance width
/// are dropped, because each one repeats the `xMin` of its glyph.
Uint8List buildHmtxWoff2(Uint8List sfnt, {int flags = 1}) {
  final tables = sfntTables(sfnt);
  final numGlyphs = ByteData.sublistView(tables['maxp']!).getUint16(4);
  final numHMetrics = ByteData.sublistView(tables['hhea']!).getUint16(34);
  final hmtx = ByteData.sublistView(tables['hmtx']!);
  final reduced = <int>[flags];
  for (var glyph = 0; glyph < numHMetrics; glyph++) {
    final advance = hmtx.getUint16(glyph * 4);
    reduced.addAll([(advance >> 8) & 0xff, advance & 0xff]);
  }
  if ((flags & 1) == 0) {
    for (var glyph = 0; glyph < numHMetrics; glyph++) {
      final bearing = hmtx.getInt16(glyph * 4 + 2);
      reduced.addAll([(bearing >> 8) & 0xff, bearing & 0xff]);
    }
  }
  if ((flags & 2) == 0) {
    for (var glyph = numHMetrics; glyph < numGlyphs; glyph++) {
      final bearing =
          hmtx.getInt16(numHMetrics * 4 + (glyph - numHMetrics) * 2);
      reduced.addAll([(bearing >> 8) & 0xff, bearing & 0xff]);
    }
  }

  final entries = <Woff2Entry>[];
  var size = 12 + tables.length * 16;
  for (final tag in tables.keys) {
    if (tag == 'hmtx') {
      entries.add(Woff2Entry('hmtx', Uint8List.fromList(reduced),
          originalLength: tables[tag]!.length, version: 1));
    } else {
      entries.add(Woff2Entry.plain(tag, tables[tag]!));
    }
    size += round4(tables[tag]!.length);
  }
  return encodeWoff2(entries, totalSfntSize: size);
}

// --- a font built by hand to reach what the fixture does not --------------

/// The component records of a composite glyph, one for each way section 5.1
/// has to measure a component: word-sized offsets, a single scale, separate
/// x and y scales, and a full two-by-two matrix, with the last one asking
/// for instructions as well.
final List<int> compositeRecords = <int>[
  0x00, 0x21, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, //
  0x00, 0x28, 0x00, 0x01, 0x00, 0x00, 0x40, 0x00, //
  0x00, 0x60, 0x00, 0x01, 0x00, 0x00, 0x40, 0x00, 0x40, 0x00, //
  0x01, 0x81, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, //
  0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
];

final List<int> compositeInstructions = <int>[0x01, 0x02, 0x03];

/// The three glyphs of the hand-built font, as `glyf` should rebuild them.
final List<int> expectedSimpleGlyph = <int>[
  0x00, 0x01, // one contour
  0x00, 0x05, 0x00, 0x0f, 0x00, 0x2d, 0x00, 0x19, // the stored bounding box
  0x00, 0x01, // the contour ends at point 1
  0x00, 0x00, // no instructions
  0x77, 0x33, // flags: the first point also carries the overlap bit
  0x0a, 0x1e, // x deltas
  0x14, // the one y delta
];

final List<int> expectedCompositeGlyph = <int>[
  0xff, 0xff, //
  0x00, 0x00, 0x00, 0x00, 0x00, 0x64, 0x00, 0x64, //
  ...compositeRecords,
  0x00, 0x03,
  ...compositeInstructions,
];

Uint8List fixedTable(int length, Map<int, int> shorts) {
  final table = Uint8List(length);
  final view = ByteData.sublistView(table);
  shorts.forEach(view.setUint16);
  return table;
}

/// Builds a WOFF 2.0 file whose transformed `glyf` holds an empty glyph, a
/// simple glyph with an explicit bounding box and the overlap bit, and a
/// composite glyph with every component shape. Its `loca` uses the long
/// form, which the shipped fixture does not.
Uint8List buildHandMadeWoff2({
  bool boxOnSimpleGlyph = true,
  bool boxOnComposite = true,
  bool boxOnEmptyGlyph = false,
  int glyfOriginalLength = 80,
}) {
  var bitmap = 0;
  final boxes = <int>[];
  if (boxOnEmptyGlyph) bitmap |= 0x80;
  if (boxOnSimpleGlyph) {
    bitmap |= 0x40;
    boxes.addAll([0x00, 0x05, 0x00, 0x0f, 0x00, 0x2d, 0x00, 0x19]);
  }
  if (boxOnComposite) {
    bitmap |= 0x20;
    boxes.addAll([0x00, 0x00, 0x00, 0x00, 0x00, 0x64, 0x00, 0x64]);
  }

  final streams = <List<int>>[
    [0x00, 0x00, 0x00, 0x01, 0xff, 0xff], // contour counts
    uint255(2), // the simple glyph's one contour has two points
    [127, 127], // point flags: both on-curve, both a five-byte triplet
    [0, 10, 0, 20, 0, 30, 0, 0, ...uint255(0), ...uint255(3)],
    compositeRecords,
    [bitmap, 0, 0, 0, ...boxes],
    compositeInstructions,
  ];
  final glyf = <int>[
    0x00, 0x00, // reserved
    0x00, 0x01, // optionFlags: an overlap bitmap follows the streams
    0x00, 0x03, // numGlyphs
    0x00, 0x01, // indexFormat: the long form of loca
    for (final stream in streams) ...uint32(stream.length),
    for (final stream in streams) ...stream,
    0x40, // the overlap bitmap: only the simple glyph
  ];

  final tables = <String, Uint8List>{
    'glyf': Uint8List.fromList(glyf),
    'loca': Uint8List(0),
    'head': fixedTable(54, {0: 1, 12: 0x5f0f, 14: 0x3cf5, 18: 1000, 50: 1}),
    'hhea': fixedTable(36, {0: 1, 34: 3}),
    'hmtx': fixedTable(12, {0: 500, 4: 600, 8: 700}),
    'maxp': fixedTable(32, {0: 1, 4: 3}),
  };
  final lengths = <String, int>{
    'glyf': glyfOriginalLength,
    'loca': 16,
    'head': 54,
    'hhea': 36,
    'hmtx': 12,
    'maxp': 32,
  };
  final entries = <Woff2Entry>[];
  var size = 12 + tables.length * 16;
  for (final tag in tables.keys) {
    // Version 0 means transformed for glyf and loca, untransformed for the
    // rest, which is exactly what this font wants.
    entries.add(Woff2Entry(tag, tables[tag]!, originalLength: lengths[tag]));
    size += round4(lengths[tag]!);
  }
  return encodeWoff2(entries, totalSfntSize: size);
}

/// A copy of [data] with the four bytes at [offset] replaced.
Uint8List withUint32(Uint8List data, int offset, int value) {
  final copy = Uint8List.fromList(data);
  ByteData.sublistView(copy).setUint32(offset, value);
  return copy;
}

void main() {
  final sfnt = File('test/assets/ABeeZee-Regular.ttf').readAsBytesSync();
  final transformed =
      File('test/assets/ABeeZee-Regular.woff2').readAsBytesSync();
  final untransformed =
      File('test/assets/ABeeZee-Regular-untransformed.woff2').readAsBytesSync();

  // The WOFF 2.0 encoder rewrote three things in 'head' that belong to the
  // file rather than to the font: it recorded when it ran, it set the bit
  // that marks the outlines as having been through a lossless transform, and
  // it cleared the checksum that the decoder has to recompute anyway.
  const headFileFields = {8, 9, 10, 11, 16, 32, 33, 34, 35};

  void expectSameFont(Uint8List rebuilt, {bool glyfMayBePadded = false}) {
    final original = sfntTables(sfnt);
    final tables = sfntTables(rebuilt);
    expect(tables.keys.toSet(), original.keys.toSet());
    for (final tag in original.keys) {
      if (tag == 'head') {
        for (var index = 0; index < original[tag]!.length; index++) {
          if (headFileFields.contains(index)) continue;
          expect(tables[tag]![index], original[tag]![index],
              reason: 'head byte $index');
        }
        continue;
      }
      if (glyfMayBePadded && (tag == 'glyf' || tag == 'loca')) continue;
      expect(tables[tag], original[tag], reason: 'table $tag');
    }
    expect(outlinesOf(rebuilt).map((o) => o.toString()).toList(),
        outlinesOf(sfnt).map((o) => o.toString()).toList());
    expect(metricsOf(rebuilt), metricsOf(sfnt));
  }

  group('a WOFF 2.0 file with nothing transformed', () {
    test('is recognised by its signature alone', () {
      expect(Woff2Converter.isWoff2(untransformed), isTrue);
      expect(Woff2Converter.isWoff2(sfnt), isFalse);
      expect(Woff2Converter.isWoff2(const []), isFalse);
    });

    test('rebuilds the font it was made from', () {
      expectSameFont(Woff2Converter.convert(untransformed));
    });

    test('rebuilds a font this test wrapped itself', () {
      expectSameFont(Woff2Converter.convert(buildPlainWoff2(sfnt)));
    });

    test('is reached through the WOFF 1.0 entry point as well', () {
      expect(WoffConverter.toSfnt(untransformed),
          Woff2Converter.convert(untransformed));
    });

    test('parses into the same font program', () {
      final direct = TrueTypeFont.fromBytes(sfnt);
      final unwrapped =
          FontProgramFactory.createFontFromBytes(untransformed, false);
      expect(unwrapped, isA<TrueTypeFont>());
      final font = unwrapped as TrueTypeFont;
      expect(font.getFontNames().getFontName(),
          direct.getFontNames().getFontName());
      expect(font.countOfGlyphs(), direct.countOfGlyphs());
      expect(font.getWidth(0x41), direct.getWidth(0x41));
      expect(
          font.getFontMetrics().getBbox(), direct.getFontMetrics().getBbox());
    });
  });

  group('a WOFF 2.0 file with glyf and loca transformed', () {
    test('restores the outline of every glyph', () {
      final rebuilt = Woff2Converter.convert(transformed);
      final restored = outlinesOf(rebuilt);
      final original = outlinesOf(sfnt);
      expect(restored.length, 268);
      for (var glyph = 0; glyph < original.length; glyph++) {
        expect(restored[glyph].contours, original[glyph].contours,
            reason: 'glyph $glyph contour count');
        expect(restored[glyph].endPoints, original[glyph].endPoints,
            reason: 'glyph $glyph contour ends');
        expect(restored[glyph].xs, original[glyph].xs,
            reason: 'glyph $glyph x coordinates');
        expect(restored[glyph].ys, original[glyph].ys,
            reason: 'glyph $glyph y coordinates');
        expect(restored[glyph].onCurve, original[glyph].onCurve,
            reason: 'glyph $glyph on-curve flags');
        expect(restored[glyph].bbox, original[glyph].bbox,
            reason: 'glyph $glyph bounding box');
        expect(restored[glyph].components, original[glyph].components,
            reason: 'glyph $glyph components');
        expect(restored[glyph].instructions, original[glyph].instructions,
            reason: 'glyph $glyph instructions');
      }
    });

    test('restores the untransformed tables byte for byte', () {
      expectSameFont(Woff2Converter.convert(transformed),
          glyfMayBePadded: true);
    });

    test(
        'restores the glyf table itself, up to the padding that rounds '
        'it off', () {
      final rebuilt = sfntTables(Woff2Converter.convert(transformed))['glyf']!;
      final original = sfntTables(sfnt)['glyf']!;
      expect(rebuilt.length, greaterThanOrEqualTo(original.length));
      expect(rebuilt.length, lessThan(original.length + 4));
      expect(Uint8List.sublistView(rebuilt, 0, original.length), original);
      expect(Uint8List.sublistView(rebuilt, original.length), everyElement(0));
    });

    test('rebuilds loca from the sizes the glyphs came out at', () {
      final tables = sfntTables(Woff2Converter.convert(transformed));
      final loca = ByteData.sublistView(tables['loca']!);
      expect(tables['loca']!.length, 2 * 269);
      expect(loca.getUint16(0), 0);
      expect(loca.getUint16(268 * 2) * 2, tables['glyf']!.length);
      // Every glyph but the last begins on a four-byte boundary.
      for (var glyph = 0; glyph < 268; glyph++) {
        expect(loca.getUint16(glyph * 2) * 2 % 4, 0, reason: 'glyph $glyph');
      }
    });

    test('recomputes the checksum the font carries for itself', () {
      final rebuilt = Woff2Converter.convert(transformed);
      final headOffset = tableOffset(rebuilt, 'head');
      final adjustment =
          ByteData.sublistView(rebuilt).getUint32(headOffset + 8);
      // Summing the whole font in 32-bit words with checkSumAdjustment
      // cleared has to leave exactly the difference the stored value makes
      // up: that is what the field is for.
      final zeroed = Uint8List.fromList(rebuilt);
      final view = ByteData.sublistView(zeroed);
      view.setUint32(headOffset + 8, 0);
      var sum = 0;
      for (var offset = 0; offset + 4 <= zeroed.length; offset += 4) {
        sum = (sum + view.getUint32(offset)) & 0xffffffff;
      }
      expect(adjustment, (0xb1b0afba - sum) & 0xffffffff);
      expect(adjustment, isNot(0));
    });
  });

  group('a transformed glyf table built by hand', () {
    test('rebuilds each kind of glyph', () {
      final tables = sfntTables(Woff2Converter.convert(buildHandMadeWoff2()));
      final glyf = tables['glyf']!;
      final loca = ByteData.sublistView(tables['loca']!);
      expect(tables['loca']!.length, 16, reason: 'the long form of loca');
      expect([
        loca.getUint32(0),
        loca.getUint32(4),
        loca.getUint32(8),
        loca.getUint32(12),
      ], [
        0,
        0,
        20,
        80
      ]);
      expect(Uint8List.sublistView(glyf, 0, 19), expectedSimpleGlyph);
      expect(Uint8List.sublistView(glyf, 19, 20), [0],
          reason: 'a glyph is padded so the next one starts on a word');
      expect(Uint8List.sublistView(glyf, 20, 77), expectedCompositeGlyph);
      expect(Uint8List.sublistView(glyf, 77), everyElement(0));
    });

    test('prefers the stored bounding box to the one it could compute', () {
      final glyf =
          sfntTables(Woff2Converter.convert(buildHandMadeWoff2()))['glyf']!;
      final view = ByteData.sublistView(glyf);
      expect([
        view.getInt16(2),
        view.getInt16(4),
        view.getInt16(6),
        view.getInt16(8),
      ], [
        5,
        15,
        45,
        25
      ]);
    });

    test('computes the bounding box when none was stored', () {
      final glyf = sfntTables(Woff2Converter.convert(
          buildHandMadeWoff2(boxOnSimpleGlyph: false)))['glyf']!;
      final view = ByteData.sublistView(glyf);
      // The two points are (10, 20) and (40, 20).
      expect([
        view.getInt16(2),
        view.getInt16(4),
        view.getInt16(6),
        view.getInt16(8),
      ], [
        10,
        20,
        40,
        20
      ]);
    });

    test('rejects a composite glyph with no bounding box of its own', () {
      expect(
          () =>
              Woff2Converter.convert(buildHandMadeWoff2(boxOnComposite: false)),
          throwsA(isA<DpdfException>()));
    });

    test('rejects an empty glyph that claims a bounding box', () {
      expect(
          () =>
              Woff2Converter.convert(buildHandMadeWoff2(boxOnEmptyGlyph: true)),
          throwsA(isA<DpdfException>()));
    });
  });

  group('the transformed hmtx table', () {
    test('gives back the side bearings it dropped', () {
      final rebuilt = Woff2Converter.convert(buildHmtxWoff2(sfnt));
      expect(sfntTables(rebuilt)['hmtx'], sfntTables(sfnt)['hmtx']);
      expect(metricsOf(rebuilt), metricsOf(sfnt));
    });

    test('is rejected when it claims to have dropped nothing', () {
      expect(() => Woff2Converter.convert(buildHmtxWoff2(sfnt, flags: 0)),
          throwsA(isA<DpdfException>()));
    });

    test('is rejected when a reserved flag bit is set', () {
      expect(() => Woff2Converter.convert(buildHmtxWoff2(sfnt, flags: 5)),
          throwsA(isA<DpdfException>()));
    });
  });

  group('a WOFF 2.0 collection', () {
    test('rebuilds every font it holds, sharing the tables once', () {
      final collection = Woff2Converter.convert(buildCollectionWoff2(sfnt, 2));
      final view = ByteData.sublistView(collection);
      expect(String.fromCharCodes(collection, 0, 4), 'ttcf');
      expect(view.getUint32(4), 0x00010000);
      expect(view.getUint32(8), 2);
      final first = view.getUint32(12);
      final second = view.getUint32(16);
      expect(first, lessThan(second));
      // Both directories describe the same tables at the same places.
      final count = view.getUint16(first + 4);
      expect(view.getUint16(second + 4), count);
      for (var index = 0; index < count; index++) {
        final a = first + 12 + index * 16;
        final b = second + 12 + index * 16;
        expect(view.getUint32(b), view.getUint32(a), reason: 'tag $index');
        expect(view.getUint32(b + 8), view.getUint32(a + 8),
            reason: 'offset $index');
        expect(view.getUint32(b + 12), view.getUint32(a + 12),
            reason: 'length $index');
      }
    });
  });

  group('the metadata and private blocks', () {
    final metadata = Uint8List.fromList(
        '<?xml version="1.0"?><metadata version="1.0"/>'.codeUnits);
    final private = Uint8List.fromList([1, 2, 3, 4, 5]);

    test('are read back as they were written', () {
      final file =
          buildPlainWoff2(sfnt, metadata: metadata, privateData: private);
      expect(Woff2Converter.extractMetadata(file), metadata);
      expect(Woff2Converter.extractPrivateData(file), private);
      expectSameFont(Woff2Converter.convert(file));
    });

    test('are absent from a file that carries neither', () {
      expect(Woff2Converter.extractMetadata(untransformed), isNull);
      expect(Woff2Converter.extractPrivateData(untransformed), isNull);
    });
  });

  group('damaged files are rejected', () {
    test('a signature that is not wOF2', () {
      final damaged = withUint32(untransformed, 0, 0x774f4646);
      expect(
          () => Woff2Converter.convert(damaged), throwsA(isA<DpdfException>()));
    });

    test('a declared length that is not the file length', () {
      final damaged = withUint32(untransformed, 8, untransformed.length + 4);
      expect(
          () => Woff2Converter.convert(damaged), throwsA(isA<DpdfException>()));
    });

    test('a reserved field that is not zero', () {
      final damaged = Uint8List.fromList(untransformed);
      damaged[15] = 1;
      expect(
          () => Woff2Converter.convert(damaged), throwsA(isA<DpdfException>()));
    });

    test('a totalSfntSize that the rebuilt font does not come to', () {
      for (final size in [46012, 46020]) {
        final damaged = withUint32(untransformed, 16, size);
        expect(() => Woff2Converter.convert(damaged),
            throwsA(isA<DpdfException>()),
            reason: 'totalSfntSize $size');
      }
    });

    test('a table count of zero', () {
      final damaged = Uint8List.fromList(untransformed);
      damaged[12] = 0;
      damaged[13] = 0;
      expect(
          () => Woff2Converter.convert(damaged), throwsA(isA<DpdfException>()));
    });

    test('a UIntBase128 that is not the shortest spelling of its value', () {
      // The first directory entry begins at 48: a flags byte, then the
      // table's original length. Pushing a 0x80 in front of that length
      // leaves the value alone and the encoding invalid.
      final damaged = <int>[
        ...untransformed.sublist(0, 49),
        0x80,
        ...untransformed.sublist(49),
      ];
      expect(() => Woff2Converter.convert(Uint8List.fromList(damaged)),
          throwsA(isA<DpdfException>()));
    });

    test('a UIntBase128 longer than five bytes', () {
      final damaged = <int>[
        ...untransformed.sublist(0, 49),
        0x81,
        0x80,
        0x80,
        0x80,
        0x80,
        ...untransformed.sublist(49),
      ];
      expect(() => Woff2Converter.convert(Uint8List.fromList(damaged)),
          throwsA(isA<DpdfException>()));
    });

    test('a Brotli stream that stops early', () {
      final damaged = Uint8List.fromList(
          untransformed.sublist(0, untransformed.length - 200));
      ByteData.sublistView(damaged).setUint32(8, damaged.length);
      final view = ByteData.sublistView(damaged);
      view.setUint32(20, view.getUint32(20) - 200);
      expect(
          () => Woff2Converter.convert(damaged), throwsA(isA<DpdfException>()));
    });

    test('a Brotli stream whose bytes have been scrambled', () {
      final damaged = Uint8List.fromList(untransformed);
      for (var offset = damaged.length ~/ 2;
          offset < damaged.length ~/ 2 + 64;
          offset++) {
        damaged[offset] ^= 0xff;
      }
      expect(
          () => Woff2Converter.convert(damaged), throwsA(isA<DpdfException>()));
    });

    test('a glyf table whose origLength is not what the transform produced',
        () {
      // The glyf entry of the fixture records 25564 bytes; the rebuilt table
      // has to come to that, give or take the padding that rounds it off.
      for (final length in [25000, 25570]) {
        final damaged = withGlyfOriginalLength(transformed, length);
        expect(() => Woff2Converter.convert(damaged),
            throwsA(isA<DpdfException>()),
            reason: 'origLength $length');
      }
    });

    test('a loca table whose origLength does not match the glyph count', () {
      final damaged = withLocaOriginalLength(transformed, 540);
      expect(
          () => Woff2Converter.convert(damaged), throwsA(isA<DpdfException>()));
    });

    test('a transformation named for a table that has none defined', () {
      final tables = sfntTables(sfnt);
      final entries = <Woff2Entry>[];
      var size = 12 + tables.length * 16;
      for (final tag in tables.keys) {
        entries.add(tag == 'cmap'
            ? Woff2Entry('cmap', tables[tag]!, version: 1)
            : Woff2Entry.plain(tag, tables[tag]!));
        size += round4(tables[tag]!.length);
      }
      expect(
          () =>
              Woff2Converter.convert(encodeWoff2(entries, totalSfntSize: size)),
          throwsA(isA<DpdfException>()));
    });

    test('a file with no tables at all', () {
      expect(() => Woff2Converter.convert(Uint8List(48)),
          throwsA(isA<DpdfException>()));
      expect(() => Woff2Converter.convert(Uint8List(20)),
          throwsA(isA<DpdfException>()));
    });
  });
}

/// Rewrites the `origLength` the fixture records for its `glyf` table.
///
/// The entry is the ninth of the directory, and its length is a UIntBase128,
/// so the replacement is spliced in rather than overwritten.
Uint8List withGlyfOriginalLength(Uint8List file, int length) =>
    withTableOriginalLength(file, 'glyf', length);

Uint8List withLocaOriginalLength(Uint8List file, int length) =>
    withTableOriginalLength(file, 'loca', length);

Uint8List withTableOriginalLength(Uint8List file, String tag, int length) {
  final count = ByteData.sublistView(file).getUint16(12);
  var cursor = 48;
  for (var index = 0; index < count; index++) {
    final flags = file[cursor++];
    final known = flags & 0x3f;
    final String name;
    if (known == 63) {
      name = String.fromCharCodes(file, cursor, cursor + 4);
      cursor += 4;
    } else {
      name = knownTagText.substring(known * 4, known * 4 + 4);
    }
    final start = cursor;
    while ((file[cursor] & 0x80) != 0) {
      cursor++;
    }
    cursor++;
    final end = cursor;
    final transformed = name == 'glyf' || name == 'loca'
        ? (flags >> 6) == 0
        : (flags >> 6) != 0;
    if (transformed) {
      while ((file[cursor] & 0x80) != 0) {
        cursor++;
      }
      cursor++;
    }
    if (name != tag) continue;
    final rebuilt = Uint8List.fromList([
      ...file.sublist(0, start),
      ...base128(length),
      ...file.sublist(end),
    ]);
    ByteData.sublistView(rebuilt).setUint32(8, rebuilt.length);
    return rebuilt;
  }
  throw StateError('no $tag table in the fixture');
}
