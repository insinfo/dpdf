import 'dart:typed_data';

import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../kernel/pdf/pdf_writer.dart';
import '../kernel/pdf/reader_properties.dart';
import '../kernel/pdf/writer_properties.dart';
import '../platform/compression.dart';
import 'pdf_compression_options.dart';
import 'pdf_image_compressor.dart';
import 'pdf_image_usage_analyzer.dart';

/// The result of compressing one document.
class PdfCompressionResult {
  /// The rewritten document.
  final Uint8List bytes;

  /// What was done and what it saved.
  final PdfCompressionReport report;

  const PdfCompressionResult(this.bytes, this.report);
}

/// Rewrites a PDF smaller without changing what a reader draws.
///
/// The passes are the ones a size reduction tool applies, in the order that
/// lets each one see the effect of the last: remove what nothing needs, share
/// what is duplicated, re-encode what is stored loosely, and then pack the
/// result into object streams behind a cross-reference stream.
///
/// The page content itself is never re-interpreted: operators, fonts and image
/// samples come through unchanged. Image *recompression* — resampling and
/// re-encoding the pixels — is a separate, lossy decision and is not done here.
class PdfCompressor {
  PdfCompressor._();

  /// Compresses [source] and returns the rewritten document with a report.
  static Future<PdfCompressionResult> compress(
    Uint8List source, {
    PdfCompressionOptions options = const PdfCompressionOptions(),
    String? password,
  }) async {
    if (options.compressionLevel < -1 || options.compressionLevel > 9) {
      throw ArgumentError.value(options.compressionLevel, 'compressionLevel',
          'must be between 0 and 9, or -1 for the deflate default');
    }
    if (options.images.targetDpi != null && options.images.targetDpi! <= 0) {
      throw ArgumentError.value(
          options.images.targetDpi, 'targetDpi', 'must be greater than zero');
    }

    final readerProperties = ReaderProperties();
    if (password != null) {
      readerProperties.setPasswordFromString(password);
    }
    final writerProperties = WriterProperties()
      ..setFullCompressionMode(options.objectStreams)
      ..setCompressionLevel(options.compressionLevel);

    final output = BytesBuilder();
    final document = PdfDocument(
      reader: PdfReader.fromBytes(source, readerProperties),
      writer: PdfWriter.fromBytesBuilder(output, properties: writerProperties),
    );
    await document.load();

    final removed = <String, int>{};
    var streamsRecompressed = 0;
    var streamBytesSaved = 0;
    var duplicatesMerged = 0;
    var orphansRemoved = 0;
    var images = PdfImageCompressionReport.empty;

    try {
      final live = await _liveObjects(document);

      if (options.removeStructureTree) {
        _removeCatalogEntries(
            document, const ['StructTreeRoot', 'MarkInfo'], removed);
      }
      if (options.removeMetadata) {
        _removeCatalogEntries(document, const ['Metadata'], removed);
      }
      await _pruneDictionaries(live, options, removed);

      Map<PdfStream, PdfImageUsage> usages = const {};
      if (options.images.targetDpi != null) {
        try {
          usages = await PdfImageUsageAnalyzer.analyze(document);
        } on Object {
          // DPI é uma otimização opcional. Se um conteúdo ou recurso danificado
          // impedir uma medição completa, preserve as dimensões armazenadas.
        }
      }
      images =
          await PdfImageCompressor.run(live, options.images, usages: usages);

      if (options.recompressStreams) {
        final saved = await _recompressStreams(live, options.compressionLevel);
        streamsRecompressed = saved.count;
        streamBytesSaved = saved.bytes;
      }

      if (options.deduplicateObjects) {
        duplicatesMerged = await _deduplicate(document, live);
      }

      if (options.removeOrphans) {
        orphansRemoved = await _removeOrphans(document);
      }

      await document.close();
    } catch (_) {
      await document.close().catchError((_) {});
      rethrow;
    }

    final rewritten = output.takeBytes();
    // A cross-reference stream and an object stream cost a fixed number of
    // bytes, so on a document that was already optimal the rewrite can be
    // larger than what it replaced. Handing that back would be a regression.
    final keptOriginal = options.neverGrow && rewritten.length >= source.length;
    final bytes = keptOriginal ? source : rewritten;

    return PdfCompressionResult(
      bytes,
      PdfCompressionReport(
        originalSize: source.length,
        compressedSize: bytes.length,
        keptOriginal: keptOriginal,
        orphansRemoved: orphansRemoved,
        duplicatesMerged: duplicatesMerged,
        streamsRecompressed: streamsRecompressed,
        streamBytesSaved: streamBytesSaved,
        entriesRemoved: Map.unmodifiable(removed),
        images: images,
      ),
    );
  }

  // --- reachability ---------------------------------------------------------

  /// Every object reachable from the trailer, in discovery order.
  ///
  /// Walking from the trailer rather than over the cross-reference table is
  /// what separates the objects the document needs from the ones an
  /// incremental update left behind.
  static Future<List<PdfObject>> _liveObjects(PdfDocument document) async {
    final seen = <PdfObject>{};
    final ordered = <PdfObject>[];
    final queue = <PdfObject>[];

    final trailer = document.fileTrailer();
    for (final key in const ['Root', 'Info']) {
      final value = trailer.getMap()?[PdfName(key)];
      if (value != null) queue.add(value);
    }

    while (queue.isNotEmpty) {
      final object = queue.removeLast();
      final resolved = await _resolve(object);
      if (resolved == null || !seen.add(resolved)) continue;
      ordered.add(resolved);

      if (resolved is PdfDictionary) {
        // A stream is a dictionary too, so this covers both.
        final map = resolved.getMap();
        if (map != null) queue.addAll(map.values);
      } else if (resolved is PdfArray) {
        for (var i = 0; i < resolved.size(); i++) {
          final item = await resolved.get(i, false);
          if (item != null) queue.add(item);
        }
      }
    }
    return ordered;
  }

  static Future<PdfObject?> _resolve(PdfObject object) async {
    if (object.objectKind() != PdfObjectType.indirectReference) return object;
    try {
      return await (object as PdfIndirectReference).targetObject(true);
    } on Object {
      // A reference into a damaged region resolves to nothing; the rewrite
      // simply carries the dangling reference over, as a reader would.
      return null;
    }
  }

  // --- pruning --------------------------------------------------------------

  static void _removeCatalogEntries(
    PdfDocument document,
    List<String> keys,
    Map<String, int> removed,
  ) {
    final catalog = document.rootCatalog().pdfRepresentation();
    for (final key in keys) {
      if (catalog.remove(PdfName(key)) != null) {
        removed[key] = (removed[key] ?? 0) + 1;
        catalog.markChanged();
      }
    }
  }

  static Future<void> _pruneDictionaries(
    List<PdfObject> live,
    PdfCompressionOptions options,
    Map<String, int> removed,
  ) async {
    final keys = <String>[
      if (options.removeThumbnails) 'Thumb',
      if (options.removePieceInfo) 'PieceInfo',
      if (options.removeMetadata) 'Metadata',
    ];
    if (keys.isEmpty) return;

    for (final object in live) {
      if (object is! PdfDictionary) continue;
      for (final key in keys) {
        if (object.remove(PdfName(key)) != null) {
          removed[key] = (removed[key] ?? 0) + 1;
          object.markChanged();
        }
      }
    }
  }

  // --- stream re-encoding ---------------------------------------------------

  /// Filters that already carry a compressed image. Deflating their output
  /// again costs time and makes the stream larger.
  static const Set<String> _imageCodecs = {
    'DCTDecode',
    'DCT',
    'JPXDecode',
    'JBIG2Decode',
    'CCITTFaxDecode',
    'CCF',
  };

  static Future<({int count, int bytes})> _recompressStreams(
    List<PdfObject> live,
    int level,
  ) async {
    var count = 0;
    var saved = 0;

    for (final object in live) {
      if (object is! PdfStream) continue;
      if (await _usesImageCodec(object)) continue;
      // A stream that carries its data outside the file is not ours to touch.
      if (object.containsKey(PdfName('F'))) continue;

      Uint8List? raw;
      Uint8List? decoded;
      try {
        raw = await object.getRawBytes();
        decoded = await object.getBytes();
      } on Object {
        // A stream that will not decode is left exactly as it is: rewriting it
        // could only lose data.
        continue;
      }
      if (raw == null || decoded == null || decoded.isEmpty) continue;

      final Uint8List candidate;
      try {
        candidate = Uint8List.fromList(
            ZLibEncoder(level: level == -1 ? 6 : level).convert(decoded));
      } on Object {
        continue;
      }
      if (candidate.length >= raw.length) continue;

      object.setData(candidate);
      object.put(PdfName.filter, PdfName('FlateDecode'));
      object.remove(PdfName('DecodeParms'));
      object.markChanged();
      count++;
      saved += raw.length - candidate.length;
    }
    return (count: count, bytes: saved);
  }

  static Future<bool> _usesImageCodec(PdfStream stream) async {
    final filter = await stream.get(PdfName.filter);
    if (filter == null) return false;
    if (filter.objectKind() == PdfObjectType.name) {
      return _imageCodecs.contains((filter as PdfName).getValue());
    }
    if (filter.objectKind() == PdfObjectType.array) {
      final array = filter as PdfArray;
      for (var i = 0; i < array.size(); i++) {
        final name = await array.nameEntry(i);
        if (name != null && _imageCodecs.contains(name.getValue())) return true;
      }
    }
    return false;
  }

  // --- deduplication --------------------------------------------------------

  /// Replaces objects with identical content by the lowest-numbered one.
  ///
  /// Identity is decided on a canonical rendering of the object: a stream by
  /// its raw payload plus its dictionary, a dictionary by its sorted entries.
  /// Only indirect objects can be shared, so a direct value is left alone.
  static Future<int> _deduplicate(
    PdfDocument document,
    List<PdfObject> live,
  ) async {
    final canonical = <String, PdfIndirectReference>{};
    final replacement = <int, PdfIndirectReference>{};

    for (final object in live) {
      final handle = object.indirectHandle();
      if (handle == null) continue;
      if (object is! PdfDictionary && object is! PdfArray) continue;

      final String key;
      try {
        key = await _fingerprint(object);
      } on Object {
        continue;
      }

      final existing = canonical[key];
      if (existing == null) {
        canonical[key] = handle;
      } else if (existing.objectNumber() != handle.objectNumber()) {
        replacement[handle.objectNumber()] = existing;
      }
    }
    if (replacement.isEmpty) return 0;

    // Rewrite every reference that points at a merged object, including the
    // ones in the trailer.
    _rewrite(document.fileTrailer(), replacement);
    for (final object in live) {
      if (object is PdfDictionary) {
        _rewrite(object, replacement);
      } else if (object is PdfArray) {
        await _rewriteArray(object, replacement);
      }
    }
    return replacement.length;
  }

  static void _rewrite(
    PdfDictionary dictionary,
    Map<int, PdfIndirectReference> replacement,
  ) {
    final map = dictionary.getMap();
    if (map == null) return;
    for (final entry in map.entries.toList()) {
      final value = entry.value;
      if (value.objectKind() != PdfObjectType.indirectReference) continue;
      final target =
          replacement[(value as PdfIndirectReference).objectNumber()];
      if (target != null) {
        dictionary.put(entry.key, target);
        dictionary.markChanged();
      }
    }
  }

  static Future<void> _rewriteArray(
    PdfArray array,
    Map<int, PdfIndirectReference> replacement,
  ) async {
    for (var i = 0; i < array.size(); i++) {
      final value = await array.get(i, false);
      if (value == null ||
          value.objectKind() != PdfObjectType.indirectReference) {
        continue;
      }
      final target =
          replacement[(value as PdfIndirectReference).objectNumber()];
      if (target != null) {
        array.set(i, target);
        array.markChanged();
      }
    }
  }

  /// A canonical string for [object], deep enough to be safe and shallow
  /// enough to be cheap: nested indirect references contribute their object
  /// number rather than their content.
  static Future<String> _fingerprint(PdfObject object) async {
    final buffer = StringBuffer();
    if (object is PdfStream) {
      final raw = await object.getRawBytes();
      buffer
        ..write('stream:')
        ..write(raw?.length ?? 0)
        ..write(':')
        ..write(raw == null ? '' : _digest(raw))
        ..write(':');
    }
    if (object is PdfDictionary) {
      final map = object.getMap() ?? const {};
      final keys = map.keys.map((k) => k.getValue()).toList()..sort();
      buffer.write('dict{');
      for (final key in keys) {
        buffer
          ..write(key)
          ..write('=')
          ..write(_shallow(map[PdfName(key)]!))
          ..write(',');
      }
      buffer.write('}');
    } else if (object is PdfArray) {
      buffer.write('array[');
      for (var i = 0; i < object.size(); i++) {
        buffer
          ..write(_shallow(await object.get(i, false)))
          ..write(',');
      }
      buffer.write(']');
    }
    return buffer.toString();
  }

  static String _shallow(PdfObject? value) {
    if (value == null) return 'null';
    switch (value.objectKind()) {
      case PdfObjectType.indirectReference:
        final reference = value as PdfIndirectReference;
        return 'R${reference.objectNumber()}_${reference.generationNumber()}';
      case PdfObjectType.name:
        return '/${(value as PdfName).getValue()}';
      case PdfObjectType.dictionary:
      case PdfObjectType.stream:
      case PdfObjectType.array:
        // A direct container is not compared by content; two objects that
        // differ only inside a direct child are simply not merged, which is
        // the safe direction to be wrong in.
        return 'inline${value.hashCode}';
      default:
        return value.toString();
    }
  }

  /// A 64-bit FNV-1a digest, written out in hex.
  ///
  /// Collision resistance is not a security property here: two streams that
  /// collide would be merged wrongly, so the digest is combined with the exact
  /// byte length by the caller, and the space is large enough that a document
  /// would need billions of distinct streams for a collision to be likely.
  static String _digest(Uint8List bytes) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * prime) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  // --- orphan removal -------------------------------------------------------

  static Future<int> _removeOrphans(PdfDocument document) async {
    // Recompute reachability: deduplication just changed which objects are
    // referenced, and the merged ones are now orphans themselves.
    final live = await _liveObjects(document);
    final keep = <int>{};
    for (final object in live) {
      final handle = object.indirectHandle();
      if (handle != null) keep.add(handle.objectNumber());
    }

    final xref = document.crossReferenceTable();
    var freed = 0;
    for (var number = 1; number < xref.size(); number++) {
      final reference = xref.get(number);
      if (reference == null || reference.isFree()) continue;
      if (keep.contains(number)) continue;
      xref.freeReference(reference);
      freed++;
    }
    return freed;
  }
}
