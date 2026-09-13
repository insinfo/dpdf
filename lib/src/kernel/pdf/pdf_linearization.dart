import 'dart:typed_data';

import '../../io/source/byte_utils.dart';
import 'pdf_array.dart';
import 'pdf_boolean.dart';
import 'pdf_dictionary.dart';
import 'pdf_literal.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_object.dart';
import 'pdf_reader.dart';
import 'pdf_stream.dart';
import 'pdf_string.dart';
import 'reader_properties.dart';

/// Writing and validation of Linearized PDF (ISO 32000-1, Annex F).
///
/// A linearized file is an ordinary PDF whose objects are laid out so that a
/// reader can display the first page after fetching only the start of the
/// file, plus hint tables that say where every other page lives. Annex F
/// describes the layout as eleven parts; this implementation writes parts 1
/// to 9 and 11 and omits only part 10, the optional overflow hint stream,
/// which is never needed because the primary hint stream is written whole.
///
/// Writing is a rewrite, not an incremental update: the objects of the source
/// file are renumbered into the two groups F.3.1 requires, so
/// [PdfLinearizer.linearize] takes complete file bytes and returns complete
/// file bytes.
class PdfLinearizer {
  PdfLinearizer._();

  static final Uint8List _header = Uint8List.fromList(
      <int>[...'%PDF-1.7\n'.codeUnits, 0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

  /// Width used for every file offset written into the linearization
  /// parameter dictionary and the first-page trailer.
  ///
  /// Those numbers are only known once the layout is fixed, and the layout
  /// depends on how many digits they take, so they are written zero padded to
  /// a constant width. Leading zeros are valid in a PDF integer — 7.5.4 uses
  /// them for every cross-reference entry.
  static const int _numberWidth = 10;

  /// The linearization parameter dictionary shall fit in the first 1024 bytes
  /// of the file (F.3.3).
  static const int _parameterDictionaryLimit = 1024;

  /// Denominator of the fractional position of a shared object reference
  /// (Table F.3, item 13).
  static const int _fractionDenominator = 4;

  /// Rewrites [source] as a linearized PDF.
  ///
  /// Throws [UnsupportedError] for an encrypted source, whose strings and
  /// streams are keyed by object number and would have to be re-encrypted
  /// under the new numbering.
  static Future<Uint8List> linearize(Uint8List source,
      {ReaderProperties? properties}) async {
    final reader = PdfReader.fromBytes(source, properties);
    try {
      await reader.read();
      if (reader.encrypted) {
        throw UnsupportedError(
            'Linearizing an encrypted PDF is not supported: the object '
            'numbering changes and every string and stream would need to be '
            're-encrypted.');
      }
      final plan = await _Plan.build(reader);
      // `await` antes de devolver: sem ele o `finally` fecha o leitor enquanto
      // `render()` ainda corre, e um erro dele escaparia de qualquer `catch`
      // em volta. Hoje `render()` nao toca no leitor, entao a falha e latente
      // — mas e mina: quem acrescentar um acesso ali quebra em silencio.
      return await plan.render();
    } finally {
      reader.close();
    }
  }
}

/// The parts of a linearized file, in the order Annex F lays them out.
enum PdfLinearizationPart {
  /// Part 1, the file header (F.3.2).
  header,

  /// Part 2, the linearization parameter dictionary (F.3.3).
  parameters,

  /// Part 3, the first-page cross-reference table and trailer (F.3.4).
  firstPageXref,

  /// Part 4, the catalogue and other document-level objects (F.3.5).
  documentLevel,

  /// Part 5, the primary hint stream (F.3.6).
  hintStream,

  /// Part 6, the first-page section (F.3.7).
  firstPage,

  /// Part 7, the remaining pages (F.3.8).
  remainingPages,

  /// Part 8, the shared objects (F.3.9).
  sharedObjects,

  /// Part 9, objects not associated with pages (F.3.10).
  otherObjects,

  /// Part 11, the main cross-reference table and trailer (F.3.11).
  mainXref,
}

/// One entry of the page offset hint table (Table F.4).
class PdfPageHint {
  /// Number of objects the page owns, including the page object itself.
  final int objectCount;

  /// Length of the page's section in bytes.
  final int pageLength;

  /// Offset of the page's section from the beginning of the file, with the
  /// primary hint stream taken out as F.4 requires.
  final int pageOffset;

  /// Offset of the page's content stream object relative to the page.
  final int contentOffset;

  /// Length of the page's content stream object, object overhead included.
  final int contentLength;

  /// Identifiers into the shared object hint table.
  final List<int> sharedIdentifiers;

  /// Fraction numerators that go with [sharedIdentifiers].
  final List<int> sharedFractions;

  const PdfPageHint({
    required this.objectCount,
    required this.pageLength,
    required this.pageOffset,
    required this.contentOffset,
    required this.contentLength,
    required this.sharedIdentifiers,
    required this.sharedFractions,
  });
}

/// One group of the shared object hint table (Table F.6).
class PdfSharedObjectGroup {
  /// Number of objects the group spans.
  final int objectCount;

  /// Length of the group in bytes.
  final int groupLength;

  /// Whether a 16-byte MD5 signature accompanies the group.
  final bool hasSignature;

  const PdfSharedObjectGroup({
    required this.objectCount,
    required this.groupLength,
    required this.hasSignature,
  });
}

/// The hint tables of a linearized file (F.4).
class PdfHintTables {
  /// Per-page entries of the page offset hint table, first page first.
  final List<PdfPageHint> pages;

  /// Least number of objects in a page (Table F.3, item 1).
  final int leastObjectCount;

  /// Offset of the first page's page object (Table F.3, item 2).
  final int firstPageObjectOffset;

  /// Least page length in bytes (Table F.3, item 4).
  final int leastPageLength;

  /// Denominator of the shared reference fractions (Table F.3, item 13).
  final int fractionDenominator;

  /// Object number of the first object of the shared objects section
  /// (Table F.5, item 1).
  final int firstSharedObjectNumber;

  /// Offset of the first object of the shared objects section
  /// (Table F.5, item 2).
  final int firstSharedObjectOffset;

  /// Number of groups that describe the first-page section (Table F.5, item 3).
  final int firstPageGroupCount;

  /// Groups of the shared object hint table, first-page groups first.
  final List<PdfSharedObjectGroup> groups;

  const PdfHintTables({
    required this.pages,
    required this.leastObjectCount,
    required this.firstPageObjectOffset,
    required this.leastPageLength,
    required this.fractionDenominator,
    required this.firstSharedObjectNumber,
    required this.firstSharedObjectOffset,
    required this.firstPageGroupCount,
    required this.groups,
  });
}

/// The result of reading the linearization of a PDF file.
///
/// [problems] lists every rule of Annex F the file breaks; an empty list means
/// the linearization information may be trusted, which is what F.3.3 asks a
/// reader to decide before using it.
class PdfLinearizationInfo {
  /// Whether a linearization parameter dictionary was found at all.
  final bool isLinearized;

  /// The `/Linearized` version identifier, when present.
  final double? version;

  /// The `/L` entry: the length the dictionary claims the file has.
  final int? declaredFileLength;

  /// The real length of the inspected bytes.
  final int actualFileLength;

  /// The `/H` entry: offset and length of the primary hint stream, followed by
  /// the overflow hint stream when the file has one.
  final List<int> hintStreamSpans;

  /// The `/O` entry: object number of the first page's page object.
  final int? firstPageObjectNumber;

  /// The `/E` entry: offset of the end of the first page.
  final int? endOfFirstPage;

  /// The `/N` entry: number of pages.
  final int? pageCount;

  /// The `/T` entry: offset of the first entry of the main cross-reference
  /// table.
  final int? mainXrefEntryOffset;

  /// The `/P` entry: page number of the first page. Default 0.
  final int firstPageNumber;

  /// Offset of the first-page cross-reference table, from the file's final
  /// `startxref`.
  final int? firstPageXrefOffset;

  /// Offset of the main cross-reference table, from the first-page trailer's
  /// `/Prev`.
  final int? mainXrefOffset;

  /// The decoded hint tables, when they could be read.
  final PdfHintTables? hintTables;

  /// Everything about the file that Annex F forbids.
  final List<String> problems;

  const PdfLinearizationInfo({
    required this.isLinearized,
    required this.version,
    required this.declaredFileLength,
    required this.actualFileLength,
    required this.hintStreamSpans,
    required this.firstPageObjectNumber,
    required this.endOfFirstPage,
    required this.pageCount,
    required this.mainXrefEntryOffset,
    required this.firstPageNumber,
    required this.firstPageXrefOffset,
    required this.mainXrefOffset,
    required this.hintTables,
    required this.problems,
  });

  /// Whether the file is linearized and every checked rule holds.
  bool get isValid => isLinearized && problems.isEmpty;

  /// Reads and validates the linearization of [bytes].
  static Future<PdfLinearizationInfo> read(Uint8List bytes,
      {ReaderProperties? properties}) async {
    return _LinearizationParser(bytes, properties).run();
  }
}

// ===========================================================================
// Writing
// ===========================================================================

/// One serialized indirect object, with the number it gets in the output.
class _Rendered {
  final int number;
  final Uint8List bytes;
  int offset = 0;

  _Rendered(this.number, this.bytes);

  int get length => bytes.length;
}

class _Plan {
  final PdfReader reader;
  final Map<int, PdfObject> objects;
  final Map<int, int> renumber = <int, int>{};

  /// Object numbers of the page objects, in page order.
  final List<int> pages;

  /// Object numbers of the page tree nodes, page objects included.
  final Set<int> pageTree;

  /// Objects belonging to each page, page object excluded.
  final List<Set<int>> pageDependencies;

  final Set<int> documentLevel;
  final List<int> firstPageSection;
  final List<List<int>> remainingPageSections;
  final List<int> sharedObjects;
  final List<int> otherObjects;

  final PdfDictionary trailer;
  final int? rootNumber;
  final int? infoNumber;

  _Plan({
    required this.reader,
    required this.objects,
    required this.pages,
    required this.pageTree,
    required this.pageDependencies,
    required this.documentLevel,
    required this.firstPageSection,
    required this.remainingPageSections,
    required this.sharedObjects,
    required this.otherObjects,
    required this.trailer,
    required this.rootNumber,
    required this.infoNumber,
  });

  static Future<_Plan> build(PdfReader reader) async {
    final trailer = reader.trailer;
    if (trailer == null) {
      throw FormatException('The source PDF has no trailer to linearize.');
    }

    // Load every live object. Object streams and cross-reference streams are
    // dropped: their content is written back as plain objects and the new
    // file gets fresh cross-reference data.
    final objects = <int, PdfObject>{};
    for (var number = 1; number < reader.xref.size(); number++) {
      final reference = reader.xref.get(number);
      if (reference == null || reference.isFree()) continue;
      final object = await reader.readObject(number);
      if (object == null) continue;
      if (object is PdfDictionary) {
        final type = await object.get(PdfName.type, false);
        if (type == PdfName.objStm || type == PdfName.xref) continue;
      }
      objects[number] = object;
    }

    final rootNumber = _referenceNumber(await trailer.get(PdfName.root, false));
    if (rootNumber == null || objects[rootNumber] is! PdfDictionary) {
      throw FormatException(
          'The source PDF has no indirect catalogue to linearize.');
    }
    final infoNumber = _referenceNumber(await trailer.get(PdfName.info, false));
    final catalog = objects[rootNumber] as PdfDictionary;

    // --- page tree -------------------------------------------------------
    final pages = <int>[];
    final pageTree = <int>{};
    final pagesRoot = _referenceNumber(await catalog.get(PdfName.pages, false));
    if (pagesRoot != null) {
      await _walkPageTree(objects, pagesRoot, pages, pageTree, <int>{});
    }
    if (pages.isEmpty) {
      throw FormatException('The source PDF has no pages to linearize.');
    }

    // --- per page closures -----------------------------------------------
    bool notPartOfTheTree(int number) =>
        !pageTree.contains(number) && objects.containsKey(number);

    final pageDependencies = <Set<int>>[];
    for (final page in pages) {
      final dependencies = <int>{};
      final dictionary = objects[page];
      if (dictionary is PdfDictionary) {
        // F.3.7: everything the page object refers to, to any depth, except
        // page tree nodes, other page objects and the thumbnail image.
        await _collectFromDictionary(objects, dictionary, dependencies,
            notPartOfTheTree, const <String>{'Thumb', 'Parent'});
      }
      pageDependencies.add(dependencies);
    }

    // --- part 4, the document-level objects ------------------------------
    final documentLevel = <int>{rootNumber};
    for (final key in const <String>[
      'ViewerPreferences',
      'OpenAction',
      'AcroForm',
      'Threads',
    ]) {
      final value = await catalog.get(PdfName(key), false);
      if (key == 'AcroForm') {
        // Only the top-level interactive form dictionary belongs here.
        final number = _referenceNumber(value);
        if (number != null && objects.containsKey(number)) {
          documentLevel.add(number);
        }
        continue;
      }
      if (key == 'Threads') {
        // The thread dictionaries, but not their information dictionaries or
        // their beads.
        final threads = _resolve(objects, value);
        final number = _referenceNumber(value);
        if (number != null && objects.containsKey(number)) {
          documentLevel.add(number);
        }
        if (threads is PdfArray) {
          for (var i = 0; i < threads.size(); i++) {
            final thread = _referenceNumber(await threads.get(i, false));
            if (thread != null && objects.containsKey(thread)) {
              documentLevel.add(thread);
            }
          }
        }
        continue;
      }
      await _collect(objects, value, documentLevel, notPartOfTheTree);
    }

    // F.3.7/F.3.10: the outline hierarchy sits with the first page when the
    // catalogue asks to open in outline mode, and at the end of the file
    // otherwise.
    final pageMode = await catalog.get(PdfName('PageMode'), false);
    final outlinesFirst =
        pageMode is PdfName && pageMode.getValue() == 'UseOutlines';
    final outlines = <int>{};
    await _collect(objects, await catalog.get(PdfName('Outlines'), false),
        outlines, notPartOfTheTree);

    // --- part 6, the first page ------------------------------------------
    final firstPage = pages.first;
    final firstPageObjects = <int>{...pageDependencies.first};
    if (outlinesFirst) firstPageObjects.addAll(outlines);
    firstPageObjects.removeAll(documentLevel);

    final firstPageSection = <int>[firstPage];
    firstPageSection.addAll(await _orderPageObjects(
        objects, firstPage, firstPageObjects, outlinesFirst ? outlines : null));

    // --- part 8, the shared objects --------------------------------------
    final firstPageOwned = firstPageSection.toSet();
    final useCount = <int, int>{};
    for (var i = 1; i < pages.length; i++) {
      for (final number in pageDependencies[i]) {
        useCount[number] = (useCount[number] ?? 0) + 1;
      }
    }
    final sharedObjects = <int>[];
    for (final entry in useCount.entries) {
      if (entry.value < 2) continue;
      if (firstPageOwned.contains(entry.key)) continue;
      if (documentLevel.contains(entry.key)) continue;
      sharedObjects.add(entry.key);
    }
    sharedObjects.sort();

    // --- part 7, the remaining pages --------------------------------------
    final claimed = <int>{
      ...firstPageOwned,
      ...documentLevel,
      ...sharedObjects,
    };
    final remainingPageSections = <List<int>>[];
    for (var i = 1; i < pages.length; i++) {
      final own =
          pageDependencies[i].where((n) => !claimed.contains(n)).toSet();
      final section = <int>[pages[i]];
      section.addAll(await _orderPageObjects(objects, pages[i], own, null));
      claimed.addAll(section);
      remainingPageSections.add(section);
    }

    // --- part 9, everything else ------------------------------------------
    final otherObjects = <int>[];
    final placed = <int>{
      ...firstPageOwned,
      ...documentLevel,
      ...sharedObjects,
      for (final section in remainingPageSections) ...section,
    };
    // Page tree nodes first, then the outline hierarchy when it lives here,
    // then the document information dictionary, then anything left over.
    final ordered = <int>[
      ...pageTree.where((n) => !placed.contains(n)),
      if (!outlinesFirst) ...outlines.where((n) => !placed.contains(n)),
      if (infoNumber != null && !placed.contains(infoNumber)) infoNumber,
    ];
    for (final number in ordered) {
      if (!objects.containsKey(number)) continue;
      if (placed.add(number)) otherObjects.add(number);
    }
    final leftovers = objects.keys.where((n) => !placed.contains(n)).toList()
      ..sort();
    for (final number in leftovers) {
      placed.add(number);
      otherObjects.add(number);
    }

    return _Plan(
      reader: reader,
      objects: objects,
      pages: pages,
      pageTree: pageTree,
      pageDependencies: pageDependencies,
      documentLevel: documentLevel,
      firstPageSection: firstPageSection,
      remainingPageSections: remainingPageSections,
      sharedObjects: sharedObjects,
      otherObjects: otherObjects,
      trailer: trailer,
      rootNumber: rootNumber,
      infoNumber: infoNumber,
    );
  }

  // --- rendering ---------------------------------------------------------

  /// Object numbers of part 4, catalogue first.
  List<int> get _documentLevelOrder {
    final rest = documentLevel.where((n) => n != rootNumber).toList()..sort();
    return <int>[rootNumber!, ...rest];
  }

  Future<Uint8List> render() async {
    // F.3.1: group two is numbered from 1, group one continues after it, and
    // the hint stream takes the very last number.
    final group2 = <int>[
      for (final section in remainingPageSections) ...section,
      ...sharedObjects,
      ...otherObjects,
    ];
    final part4 = _documentLevelOrder;
    final group1 = <int>[...part4, ...firstPageSection];

    var next = 1;
    for (final number in group2) {
      renumber[number] = next++;
    }
    final parameterNumber = next++;
    for (final number in group1) {
      renumber[number] = next++;
    }
    final hintNumber = next++;
    final size = next;

    // Serialize every object once. Bodies do not depend on file offsets, so
    // this is done a single time and reused across layout iterations.
    final bodies = <int, _Rendered>{};
    for (final number in <int>[...group2, ...group1]) {
      bodies[number] = _Rendered(renumber[number]!,
          await _serialize(renumber[number]!, objects[number]!));
    }

    final firstPageXref = _firstPageXrefLength(group1.length);
    final mainXref = _mainXrefLength(group2.length, size);

    // Two passes: the hint stream is the only part whose size depends on the
    // layout, so lay the file out with an assumed hint size, rebuild the hint
    // stream, and pad it back to the assumed size if it came out shorter.
    var hintPayloadSize = 0;
    Uint8List? hintObject;
    late _Layout layout;
    for (var attempt = 0; attempt < 8; attempt++) {
      final hintObjectSize = hintObject?.length ??
          _hintObjectLength(hintNumber, hintPayloadSize, 0, 0, 0);
      layout = _Layout(
        headerLength: PdfLinearizer._header.length,
        parameterLength: _parameterDictionaryLength(parameterNumber),
        firstPageXrefLength: firstPageXref,
        mainXrefLength: mainXref,
        hintObjectLength: hintObjectSize,
        part4: part4,
        part6: firstPageSection,
        group2: group2,
        bodies: bodies,
      );
      final hint = await _buildHintStream(layout, hintNumber, group2);
      if (hintObject != null && hint.length <= hintObject.length) {
        // Converged: pad the payload so the object keeps the assumed size.
        hintObject = await _buildHintStreamPadded(
            layout, hintNumber, group2, hintObject.length);
        break;
      }
      hintObject = hint;
      hintPayloadSize = hint.length;
    }

    layout = _Layout(
      headerLength: PdfLinearizer._header.length,
      parameterLength: _parameterDictionaryLength(parameterNumber),
      firstPageXrefLength: firstPageXref,
      mainXrefLength: mainXref,
      hintObjectLength: hintObject!.length,
      part4: part4,
      part6: firstPageSection,
      group2: group2,
      bodies: bodies,
    );

    // --- assemble ---------------------------------------------------------
    final out = BytesBuilder();
    out.add(PdfLinearizer._header);
    out.add(await _parameterDictionary(
      number: parameterNumber,
      fileLength: layout.fileLength,
      hintOffset: layout.hintOffset,
      hintLength: hintObject.length,
      firstPageObject: renumber[pages.first]!,
      endOfFirstPage: layout.endOfFirstPage,
      pageCount: pages.length,
      mainXrefEntryOffset: layout.mainXrefFirstEntryOffset,
    ));
    out.add(_firstPageXrefSection(
      layout: layout,
      firstNumber: renumber[part4.first]!,
      parameterNumber: parameterNumber,
      hintNumber: hintNumber,
      hintOffset: layout.hintOffset,
      size: size,
      group1: group1,
      bodies: bodies,
    ));
    for (final number in part4) {
      out.add(bodies[number]!.bytes);
    }
    out.add(hintObject);
    for (final number in firstPageSection) {
      out.add(bodies[number]!.bytes);
    }
    for (final number in group2) {
      out.add(bodies[number]!.bytes);
    }
    out.add(_mainXrefSection(
      layout: layout,
      group2: group2,
      bodies: bodies,
      size: size,
    ));

    final result = out.toBytes();
    if (result.length != layout.fileLength) {
      throw StateError('Linearization produced ${result.length} bytes but '
          'planned ${layout.fileLength}.');
    }
    return result;
  }

  // --- part 2 -------------------------------------------------------------

  static String _padded(int value) =>
      value.toString().padLeft(PdfLinearizer._numberWidth, '0');

  int _parameterDictionaryLength(int number) =>
      _parameterDictionaryBytes(number, 0, 0, 0, 0, 0, 0, 0).length;

  static Uint8List _parameterDictionaryBytes(
      int number,
      int fileLength,
      int hintOffset,
      int hintLength,
      int firstPageObject,
      int endOfFirstPage,
      int pageCount,
      int mainXrefEntryOffset) {
    final buffer = StringBuffer()
      ..write('$number 0 obj\n')
      ..write('<< /Linearized 1 /L ${_padded(fileLength)}')
      ..write(' /H [ ${_padded(hintOffset)} ${_padded(hintLength)} ]')
      ..write(' /O ${_padded(firstPageObject)}')
      ..write(' /E ${_padded(endOfFirstPage)}')
      ..write(' /N ${_padded(pageCount)}')
      ..write(' /T ${_padded(mainXrefEntryOffset)} >>\n')
      ..write('endobj\n');
    final bytes = ByteUtils.getIsoBytes(buffer.toString());
    if (PdfLinearizer._header.length + bytes.length >
        PdfLinearizer._parameterDictionaryLimit) {
      throw StateError('The linearization parameter dictionary does not fit '
          'in the first ${PdfLinearizer._parameterDictionaryLimit} bytes.');
    }
    return bytes;
  }

  Future<Uint8List> _parameterDictionary({
    required int number,
    required int fileLength,
    required int hintOffset,
    required int hintLength,
    required int firstPageObject,
    required int endOfFirstPage,
    required int pageCount,
    required int mainXrefEntryOffset,
  }) async {
    return _parameterDictionaryBytes(number, fileLength, hintOffset, hintLength,
        firstPageObject, endOfFirstPage, pageCount, mainXrefEntryOffset);
  }

  // --- parts 3 and 11 -----------------------------------------------------

  int _firstPageXrefLength(int group1Count) {
    // subsection header + entries + trailer + dummy startxref + EOF
    final entries = group1Count + 2; // parameter dictionary and hint stream
    return _xrefSectionLength(
        first: 1, count: entries, trailerLength: _firstPageTrailerLength());
  }

  int _mainXrefLength(int group2Count, int size) {
    return _xrefSectionLength(
        first: 0,
        count: group2Count + 1,
        trailerLength: _mainTrailerLength(size));
  }

  int _xrefSectionLength(
      {required int first, required int count, required int trailerLength}) {
    final header = 'xref\n${_padded(first)} ${_padded(count)}\n'.length;
    return header + count * 20 + trailerLength;
  }

  /// The first-page trailer's length, measured on the values it will really
  /// carry.
  ///
  /// `/Size`, `/Prev` and `startxref` are written through [_padded] and so have
  /// a constant width, but `/Root` and `/Info` carry plain object numbers, and
  /// `/Info` is omitted entirely when the document has no information
  /// dictionary. Measuring with zeroes would therefore under-count by the
  /// digits of the root number plus the whole `/Info` clause, and the layout
  /// would plan a shorter file than it goes on to write.
  int _firstPageTrailerLength() => _firstPageTrailerBytes(
        0,
        0,
        renumber[rootNumber] ?? 0,
        infoNumber == null ? 0 : renumber[infoNumber] ?? 0,
        0,
      ).length;

  int _mainTrailerLength(int size) =>
      ByteUtils.getIsoBytes('trailer\n<< /Size ${_padded(size)} >>\n'
              'startxref\n${_padded(0)}\n%%EOF\n')
          .length;

  Uint8List _firstPageTrailerBytes(
      int size, int mainXrefOffset, int rootNew, int infoNew, int _) {
    final buffer = StringBuffer()
      ..write('trailer\n<< /Size ${_padded(size)}')
      ..write(' /Prev ${_padded(mainXrefOffset)}')
      ..write(' /Root $rootNew 0 R');
    if (infoNew > 0) buffer.write(' /Info $infoNew 0 R');
    buffer
      ..write(' >>\n')
      ..write('startxref\n${_padded(0)}\n%%EOF\n');
    return ByteUtils.getIsoBytes(buffer.toString());
  }

  Uint8List _firstPageXrefSection({
    required _Layout layout,
    required int firstNumber,
    required int parameterNumber,
    required int hintNumber,
    required int hintOffset,
    required int size,
    required List<int> group1,
    required Map<int, _Rendered> bodies,
  }) {
    // F.3.4: one subsection, no free entries, the parameter dictionary at the
    // start and the primary hint stream at the end.
    final buffer = StringBuffer()
      ..write('xref\n')
      ..write('${_padded(parameterNumber)} ${_padded(group1.length + 2)}\n')
      ..write(_xrefEntry(layout.parameterOffset, 0));
    for (final number in group1) {
      buffer.write(_xrefEntry(layout.offsetOf(number), 0));
    }
    buffer.write(_xrefEntry(hintOffset, 0));
    final head = ByteUtils.getIsoBytes(buffer.toString());
    final trailer = _firstPageTrailerBytes(
        size,
        layout.mainXrefOffset,
        renumber[rootNumber]!,
        infoNumber == null ? 0 : renumber[infoNumber]!,
        0);
    final out = BytesBuilder()
      ..add(head)
      ..add(trailer);
    return out.toBytes();
  }

  Uint8List _mainXrefSection({
    required _Layout layout,
    required List<int> group2,
    required Map<int, _Rendered> bodies,
    required int size,
  }) {
    // F.3.11: one subsection from object 0, whose entry is the only free one.
    final buffer = StringBuffer()
      ..write('xref\n')
      ..write('${_padded(0)} ${_padded(group2.length + 1)}\n')
      ..write('0000000000 65535 f \n');
    for (final number in group2) {
      buffer.write(_xrefEntry(layout.offsetOf(number), 0));
    }
    buffer
      ..write('trailer\n<< /Size ${_padded(size)} >>\n')
      ..write('startxref\n${_padded(layout.firstPageXrefOffset)}\n%%EOF\n');
    return ByteUtils.getIsoBytes(buffer.toString());
  }

  static String _xrefEntry(int offset, int generation) =>
      '${offset.toString().padLeft(10, '0')} '
      '${generation.toString().padLeft(5, '0')} n \n';

  // --- part 5, the hint tables -------------------------------------------

  int _hintObjectLength(int number, int payload, int _, int __, int ___) {
    return _hintObjectBytes(number, Uint8List(payload), <String, int>{}).length;
  }

  static Uint8List _hintObjectBytes(
      int number, Uint8List payload, Map<String, int> tableOffsets) {
    final buffer = StringBuffer()
      ..write('$number 0 obj\n')
      ..write('<< /Length ${_padded(payload.length)}');
    for (final entry in tableOffsets.entries) {
      buffer.write(' /${entry.key} ${_padded(entry.value)}');
    }
    buffer.write(' >>\nstream\n');
    final out = BytesBuilder()
      ..add(ByteUtils.getIsoBytes(buffer.toString()))
      ..add(payload)
      ..add(ByteUtils.getIsoBytes('\nendstream\nendobj\n'));
    return out.toBytes();
  }

  Future<Uint8List> _buildHintStream(
      _Layout layout, int number, List<int> group2) async {
    final tables = await _hintTables(layout, group2);
    return _hintObjectBytes(number, tables.$1, tables.$2);
  }

  Future<Uint8List> _buildHintStreamPadded(
      _Layout layout, int number, List<int> group2, int targetLength) async {
    final tables = await _hintTables(layout, group2);
    var payload = tables.$1;
    var object = _hintObjectBytes(number, payload, tables.$2);
    if (object.length > targetLength) return object;
    // Trailing bytes past the last hint table are never read: every table is
    // located by an explicit offset in the stream dictionary.
    final padding = targetLength - object.length;
    final padded = Uint8List(payload.length + padding);
    padded.setRange(0, payload.length, payload);
    object = _hintObjectBytes(number, padded, tables.$2);
    return object;
  }

  /// Builds the page offset and shared object hint tables (F.4).
  Future<(Uint8List, Map<String, int>)> _hintTables(
      _Layout layout, List<int> group2) async {
    // F.4: positions in a hint table are expressed as if the primary hint
    // stream were not in the file.
    int adjusted(int offset) =>
        offset > layout.hintOffset ? offset - layout.hintObjectLength : offset;

    final sections = <List<int>>[firstPageSection, ...remainingPageSections];

    // Groups of the shared object hint table. The first-page section is split
    // so that every object another page refers to becomes its own group and
    // each run in between becomes one group (F.4.2).
    final referencedFromOtherPages = <int>{};
    for (var i = 1; i < pages.length; i++) {
      referencedFromOtherPages.addAll(pageDependencies[i]);
    }
    final firstPageGroups = <List<int>>[];
    final groupOfObject = <int, int>{};
    for (final number in firstPageSection) {
      final isShared = referencedFromOtherPages.contains(number);
      if (isShared ||
          firstPageGroups.isEmpty ||
          groupOfObject[firstPageGroups.last.first] == -1) {
        firstPageGroups.add(<int>[number]);
        groupOfObject[number] = isShared ? firstPageGroups.length - 1 : -1;
        if (!isShared) groupOfObject[number] = -1;
      } else {
        firstPageGroups.last.add(number);
        groupOfObject[number] = -1;
      }
      if (isShared) groupOfObject[number] = firstPageGroups.length - 1;
    }
    // Recompute the index of every first-page object now that the groups are
    // known, so a reference from another page can name its group.
    for (var g = 0; g < firstPageGroups.length; g++) {
      for (final number in firstPageGroups[g]) {
        groupOfObject[number] = g;
      }
    }
    final sharedGroups = <List<int>>[
      for (final number in sharedObjects) <int>[number]
    ];
    for (var i = 0; i < sharedObjects.length; i++) {
      groupOfObject[sharedObjects[i]] = firstPageGroups.length + i;
    }

    // --- per page values ---------------------------------------------------
    final objectCounts = <int>[];
    final pageLengths = <int>[];
    final pageOffsets = <int>[];
    final contentOffsets = <int>[];
    final contentLengths = <int>[];
    final sharedIds = <List<int>>[];
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      objectCounts.add(section.length);
      var length = 0;
      for (final number in section) {
        length += layout.bodies[number]!.length;
      }
      pageLengths.add(length);
      pageOffsets.add(adjusted(layout.offsetOf(section.first)));

      final contents = await _contentStreamNumber(pages[i]);
      if (contents != null && layout.bodies.containsKey(contents)) {
        contentOffsets
            .add(layout.offsetOf(contents) - layout.offsetOf(section.first));
        contentLengths.add(layout.bodies[contents]!.length);
      } else {
        contentOffsets.add(0);
        contentLengths.add(0);
      }

      if (i == 0) {
        sharedIds.add(const <int>[]);
      } else {
        final identifiers = <int>{};
        for (final number in pageDependencies[i]) {
          final group = groupOfObject[number];
          if (group != null) identifiers.add(group);
        }
        final sorted = identifiers.toList()..sort();
        sharedIds.add(sorted);
      }
    }

    final leastObjects = objectCounts.reduce((a, b) => a < b ? a : b);
    final mostObjects = objectCounts.reduce((a, b) => a > b ? a : b);
    final leastLength = pageLengths.reduce((a, b) => a < b ? a : b);
    final mostLength = pageLengths.reduce((a, b) => a > b ? a : b);
    final leastContentOffset = contentOffsets.reduce((a, b) => a < b ? a : b);
    final mostContentOffset = contentOffsets.reduce((a, b) => a > b ? a : b);
    final leastContentLength = contentLengths.reduce((a, b) => a < b ? a : b);
    final mostContentLength = contentLengths.reduce((a, b) => a > b ? a : b);
    final mostSharedRefs =
        sharedIds.map((e) => e.length).reduce((a, b) => a > b ? a : b);
    var greatestIdentifier = 0;
    for (final list in sharedIds) {
      for (final id in list) {
        if (id > greatestIdentifier) greatestIdentifier = id;
      }
    }

    final objectBits = _bitsFor(mostObjects - leastObjects);
    final lengthBits = _bitsFor(mostLength - leastLength);
    final contentOffsetBits = _bitsFor(mostContentOffset - leastContentOffset);
    final contentLengthBits = _bitsFor(mostContentLength - leastContentLength);
    final sharedCountBits = _bitsFor(mostSharedRefs);
    final identifierBits = _bitsFor(greatestIdentifier);
    final fractionBits = _bitsFor(PdfLinearizer._fractionDenominator);

    final writer = _BitWriter();
    // Table F.3, header section.
    writer.write(leastObjects, 32);
    writer.write(adjusted(layout.offsetOf(firstPageSection.first)), 32);
    writer.write(objectBits, 16);
    writer.write(leastLength, 32);
    writer.write(lengthBits, 16);
    writer.write(leastContentOffset, 32);
    writer.write(contentOffsetBits, 16);
    writer.write(leastContentLength, 32);
    writer.write(contentLengthBits, 16);
    writer.write(sharedCountBits, 16);
    writer.write(identifierBits, 16);
    writer.write(fractionBits, 16);
    writer.write(PdfLinearizer._fractionDenominator, 16);

    // Table F.4, per page, item by item across all pages.
    for (final value in objectCounts) {
      writer.write(value - leastObjects, objectBits);
    }
    for (final value in pageLengths) {
      writer.write(value - leastLength, lengthBits);
    }
    for (final list in sharedIds) {
      writer.write(list.length, sharedCountBits);
    }
    for (var i = 1; i < sharedIds.length; i++) {
      for (final id in sharedIds[i]) {
        writer.write(id, identifierBits);
      }
    }
    for (var i = 1; i < sharedIds.length; i++) {
      for (var j = 0; j < sharedIds[i].length; j++) {
        // Table F.4, item 5: the denominator itself means the object is needed
        // before the image XObjects at the end of the page, which is the only
        // claim that can be made without parsing the content stream.
        writer.write(PdfLinearizer._fractionDenominator, fractionBits);
      }
    }
    for (final value in contentOffsets) {
      writer.write(value - leastContentOffset, contentOffsetBits);
    }
    for (final value in contentLengths) {
      writer.write(value - leastContentLength, contentLengthBits);
    }
    writer.align();

    final sharedTableOffset = writer.length;

    // Table F.5, shared object hint table header.
    final groups = <List<int>>[...firstPageGroups, ...sharedGroups];
    final groupLengths = <int>[
      for (final group in groups)
        group.fold<int>(0, (sum, n) => sum + layout.bodies[n]!.length)
    ];
    final leastGroupLength =
        groupLengths.isEmpty ? 0 : groupLengths.reduce((a, b) => a < b ? a : b);
    final mostGroupLength =
        groupLengths.isEmpty ? 0 : groupLengths.reduce((a, b) => a > b ? a : b);
    final mostGroupObjects = groups.isEmpty
        ? 0
        : groups.map((g) => g.length).reduce((a, b) => a > b ? a : b);
    final groupObjectBits = _bitsFor(mostGroupObjects);
    final groupLengthBits = _bitsFor(mostGroupLength - leastGroupLength);

    final firstSharedNumber =
        sharedObjects.isEmpty ? 0 : renumber[sharedObjects.first]!;
    final firstSharedOffset = sharedObjects.isEmpty
        ? 0
        : adjusted(layout.offsetOf(sharedObjects.first));

    writer.write(firstSharedNumber, 32);
    writer.write(firstSharedOffset, 32);
    writer.write(firstPageGroups.length, 32);
    writer.write(groups.length, 32);
    writer.write(groupObjectBits, 16);
    writer.write(leastGroupLength, 32);
    writer.write(groupLengthBits, 16);

    // Table F.6, group entries, item by item across all groups.
    for (final length in groupLengths) {
      writer.write(length - leastGroupLength, groupLengthBits);
    }
    for (var i = 0; i < groups.length; i++) {
      writer.write(0, 1); // no shared object signature
    }
    for (final group in groups) {
      writer.write(group.length - 1, groupObjectBits);
    }
    writer.align();

    return (writer.takeBytes(), <String, int>{'S': sharedTableOffset});
  }

  Future<int?> _contentStreamNumber(int pageNumber) async {
    final page = objects[pageNumber];
    if (page is! PdfDictionary) return null;
    final contents = await page.get(PdfName.contents, false);
    final direct = _referenceNumber(contents);
    if (direct != null) return direct;
    final resolved = _resolve(objects, contents);
    if (resolved is PdfArray && resolved.size() > 0) {
      return _referenceNumber(await resolved.get(0, false));
    }
    return null;
  }

  // --- object serialization ----------------------------------------------

  Future<Uint8List> _serialize(int number, PdfObject object) async {
    final out = BytesBuilder();
    out.add(ByteUtils.getIsoBytes('$number 0 obj\n'));
    await _writeValue(out, object, top: true);
    out.add(ByteUtils.getIsoBytes('\nendobj\n'));
    return out.toBytes();
  }

  Future<void> _writeValue(BytesBuilder out, PdfObject object,
      {bool top = false}) async {
    if (object is PdfIndirectReference) {
      final mapped = renumber[object.objectNumber()];
      out.add(ByteUtils.getIsoBytes(mapped == null ? 'null' : '$mapped 0 R'));
      return;
    }
    if (!top && object.indirectHandle() != null) {
      final mapped = renumber[object.indirectHandle()!.objectNumber()];
      out.add(ByteUtils.getIsoBytes(mapped == null ? 'null' : '$mapped 0 R'));
      return;
    }
    switch (object.objectKind()) {
      case PdfObjectType.nullType:
        out.add(ByteUtils.getIsoBytes('null'));
        break;
      case PdfObjectType.boolean:
        out.add(ByteUtils.getIsoBytes(
            (object as PdfBoolean).getValue() ? 'true' : 'false'));
        break;
      case PdfObjectType.number:
        out.add(ByteUtils.getIsoBytes((object as PdfNumber).toString()));
        break;
      case PdfObjectType.name:
        out.add(ByteUtils.getIsoBytes('/'));
        out.add((object as PdfName).getInternalContent() ?? Uint8List(0));
        break;
      case PdfObjectType.literal:
        out.add((object as PdfLiteral).getInternalContent() ?? Uint8List(0));
        break;
      case PdfObjectType.string:
        _writeString(out, object as PdfString);
        break;
      case PdfObjectType.array:
        await _writeArray(out, object as PdfArray);
        break;
      case PdfObjectType.dictionary:
        await _writeDictionary(out, object as PdfDictionary);
        break;
      case PdfObjectType.stream:
        await _writeStream(out, object as PdfStream);
        break;
      case PdfObjectType.indirectReference:
        break;
    }
  }

  void _writeString(BytesBuilder out, PdfString string) {
    final bytes = string.getValueBytes() ?? Uint8List(0);
    if (string.isHexWriting()) {
      final buffer = StringBuffer('<');
      for (final b in bytes) {
        buffer.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
      }
      buffer.write('>');
      out.add(ByteUtils.getIsoBytes(buffer.toString()));
      return;
    }
    out.addByte(0x28);
    for (final b in bytes) {
      if (b == 0x28 || b == 0x29 || b == 0x5C) out.addByte(0x5C);
      out.addByte(b);
    }
    out.addByte(0x29);
  }

  Future<void> _writeArray(BytesBuilder out, PdfArray array) async {
    out.addByte(0x5B);
    for (var i = 0; i < array.size(); i++) {
      if (i > 0) out.addByte(0x20);
      final value = await array.get(i, false);
      if (value == null) {
        out.add(ByteUtils.getIsoBytes('null'));
      } else {
        await _writeValue(out, value);
      }
    }
    out.addByte(0x5D);
  }

  Future<void> _writeDictionary(BytesBuilder out, PdfDictionary dictionary,
      {Map<String, PdfObject>? overrides}) async {
    out.add(ByteUtils.getIsoBytes('<<'));
    for (final key in dictionary.keySet()) {
      final override = overrides?[key.getValue()];
      final value = override ?? await dictionary.get(key, false);
      out.add(ByteUtils.getIsoBytes('/'));
      out.add(key.getInternalContent() ?? Uint8List(0));
      out.addByte(0x20);
      if (value == null) {
        out.add(ByteUtils.getIsoBytes('null'));
      } else {
        await _writeValue(out, value);
      }
      out.addByte(0x20);
    }
    if (overrides != null) {
      for (final entry in overrides.entries) {
        if (dictionary.containsKey(PdfName(entry.key))) continue;
        out.add(ByteUtils.getIsoBytes('/${entry.key} '));
        await _writeValue(out, entry.value);
        out.addByte(0x20);
      }
    }
    out.add(ByteUtils.getIsoBytes('>>'));
  }

  Future<void> _writeStream(BytesBuilder out, PdfStream stream) async {
    final bytes = await stream.getBytes(false) ?? Uint8List(0);
    await _writeDictionary(out, stream, overrides: <String, PdfObject>{
      'Length': PdfNumber.fromInt(bytes.length)
    });
    out.add(ByteUtils.getIsoBytes('\nstream\n'));
    out.add(bytes);
    out.add(ByteUtils.getIsoBytes('\nendstream'));
  }

  // --- helpers ------------------------------------------------------------

  static int _bitsFor(int value) {
    if (value <= 0) return 1;
    var bits = 0;
    var remaining = value;
    while (remaining > 0) {
      bits++;
      remaining >>= 1;
    }
    return bits;
  }

  static int? _referenceNumber(PdfObject? object) =>
      object is PdfIndirectReference ? object.objectNumber() : null;

  static PdfObject? _resolve(Map<int, PdfObject> objects, PdfObject? object) {
    if (object is PdfIndirectReference) return objects[object.objectNumber()];
    return object;
  }

  static Future<void> _walkPageTree(Map<int, PdfObject> objects, int node,
      List<int> pages, Set<int> tree, Set<int> seen) async {
    if (!seen.add(node)) return;
    final dictionary = objects[node];
    if (dictionary is! PdfDictionary) return;
    tree.add(node);
    final kids = _resolve(objects, await dictionary.get(PdfName.kids, false));
    if (kids is PdfArray) {
      for (var i = 0; i < kids.size(); i++) {
        final child = _referenceNumber(await kids.get(i, false));
        if (child == null) continue;
        await _walkPageTree(objects, child, pages, tree, seen);
      }
      return;
    }
    // A node with no /Kids is a leaf page.
    pages.add(node);
  }

  static Future<void> _collect(Map<int, PdfObject> objects, PdfObject? object,
      Set<int> into, bool Function(int) allow) async {
    if (object == null) return;
    if (object is PdfIndirectReference) {
      final number = object.objectNumber();
      if (!allow(number) || !into.add(number)) return;
      await _collect(objects, objects[number], into, allow);
      return;
    }
    if (object is PdfArray) {
      for (var i = 0; i < object.size(); i++) {
        await _collect(objects, await object.get(i, false), into, allow);
      }
      return;
    }
    if (object is PdfDictionary) {
      await _collectFromDictionary(
          objects, object, into, allow, const <String>{});
    }
  }

  static Future<void> _collectFromDictionary(
      Map<int, PdfObject> objects,
      PdfDictionary dictionary,
      Set<int> into,
      bool Function(int) allow,
      Set<String> skipKeys) async {
    for (final key in dictionary.keySet()) {
      if (skipKeys.contains(key.getValue())) continue;
      await _collect(objects, await dictionary.get(key, false), into, allow);
    }
  }

  /// Orders the objects of a page section as F.3.7 recommends.
  static Future<List<int>> _orderPageObjects(Map<int, PdfObject> objects,
      int pageNumber, Set<int> members, Set<int>? outlines) async {
    final page = objects[pageNumber];
    final ordered = <int>[];
    final remaining = <int>{...members};

    Future<void> take(PdfObject? value) async {
      final collected = <int>{};
      await _collect(objects, value, collected, (n) => remaining.contains(n));
      for (final number in collected) {
        if (remaining.remove(number)) ordered.add(number);
      }
    }

    if (page is PdfDictionary) {
      // a) annotations, b) beads, c) the resource dictionary and its objects,
      // e) the contents, f) image XObjects, g) embedded font programs.
      await take(await page.get(PdfName('Annots'), false));
      await take(await page.get(PdfName('B'), false));
      if (outlines != null) {
        for (final number in outlines) {
          if (remaining.remove(number)) ordered.add(number);
        }
      }
      await take(await page.get(PdfName.resources, false));
      await take(await page.get(PdfName.contents, false));
    }

    // Whatever is left, with image XObjects and font files last because a
    // reader defers both.
    final deferred = <int>[];
    final rest = remaining.toList()..sort();
    for (final number in rest) {
      final object = objects[number];
      if (object is PdfStream) {
        final subtype = await object.get(PdfName.subtype, false);
        if (subtype is PdfName && subtype.getValue() == 'Image') {
          deferred.add(number);
          continue;
        }
      }
      ordered.add(number);
    }
    ordered.addAll(deferred);
    return ordered;
  }
}

/// Byte positions of every part of the file, for one assumed hint-stream size.
class _Layout {
  final int headerLength;
  final int parameterLength;
  final int firstPageXrefLength;
  final int mainXrefLength;
  final int hintObjectLength;
  final List<int> part4;
  final List<int> part6;
  final List<int> group2;
  final Map<int, _Rendered> bodies;

  late final Map<int, int> _offsets = _computeOffsets();

  _Layout({
    required this.headerLength,
    required this.parameterLength,
    required this.firstPageXrefLength,
    required this.mainXrefLength,
    required this.hintObjectLength,
    required this.part4,
    required this.part6,
    required this.group2,
    required this.bodies,
  });

  int get parameterOffset => headerLength;
  int get firstPageXrefOffset => parameterOffset + parameterLength;
  int get part4Offset => firstPageXrefOffset + firstPageXrefLength;

  int get hintOffset {
    var offset = part4Offset;
    for (final number in part4) {
      offset += bodies[number]!.length;
    }
    return offset;
  }

  int get part6Offset => hintOffset + hintObjectLength;

  int get endOfFirstPage {
    var offset = part6Offset;
    for (final number in part6) {
      offset += bodies[number]!.length;
    }
    return offset;
  }

  int get mainXrefOffset {
    var offset = endOfFirstPage;
    for (final number in group2) {
      offset += bodies[number]!.length;
    }
    return offset;
  }

  /// F.3.3: `/T` is the offset of the white space that precedes the entry for
  /// object 0, not the offset of the `xref` line itself.
  int get mainXrefFirstEntryOffset {
    final header = 'xref\n'
        '${_Plan._padded(0)} ${_Plan._padded(group2.length + 1)}\n';
    return mainXrefOffset + header.length - 1;
  }

  int get fileLength => mainXrefOffset + mainXrefLength;

  int offsetOf(int oldNumber) {
    final offset = _offsets[oldNumber];
    if (offset == null) {
      throw StateError('No layout offset for object $oldNumber.');
    }
    return offset;
  }

  Map<int, int> _computeOffsets() {
    final offsets = <int, int>{};
    var position = part4Offset;
    for (final number in part4) {
      offsets[number] = position;
      position += bodies[number]!.length;
    }
    position += hintObjectLength;
    for (final number in part6) {
      offsets[number] = position;
      position += bodies[number]!.length;
    }
    for (final number in group2) {
      offsets[number] = position;
      position += bodies[number]!.length;
    }
    return offsets;
  }
}

/// Most significant bit first writer, as F.4 requires of the hint tables.
class _BitWriter {
  final BytesBuilder _out = BytesBuilder();
  int _current = 0;
  int _bits = 0;

  int get length => _out.length + (_bits > 0 ? 1 : 0);

  void write(int value, int bitCount) {
    for (var i = bitCount - 1; i >= 0; i--) {
      _current = (_current << 1) | ((value >> i) & 1);
      _bits++;
      if (_bits == 8) {
        _out.addByte(_current & 0xFF);
        _current = 0;
        _bits = 0;
      }
    }
  }

  /// Pads to the next byte boundary; F.4 starts every hint table on one.
  void align() {
    if (_bits == 0) return;
    _out.addByte((_current << (8 - _bits)) & 0xFF);
    _current = 0;
    _bits = 0;
  }

  Uint8List takeBytes() {
    align();
    return _out.toBytes();
  }
}

/// Most significant bit first reader for the hint tables.
class _BitReader {
  final Uint8List _data;
  int _bitPosition;

  _BitReader(this._data, [int byteOffset = 0]) : _bitPosition = byteOffset * 8;

  int read(int bitCount) {
    var value = 0;
    for (var i = 0; i < bitCount; i++) {
      final byte = _bitPosition >> 3;
      if (byte >= _data.length) {
        throw FormatException('A hint table ends before its last field.');
      }
      final bit = (_data[byte] >> (7 - (_bitPosition & 7))) & 1;
      value = (value << 1) | bit;
      _bitPosition++;
    }
    return value;
  }
}

// ===========================================================================
// Reading and validation
// ===========================================================================

class _LinearizationParser {
  final Uint8List bytes;
  final ReaderProperties? properties;
  final List<String> problems = <String>[];

  _LinearizationParser(this.bytes, this.properties);

  Future<PdfLinearizationInfo> run() async {
    final reader = PdfReader.fromBytes(bytes, properties);
    try {
      await reader.read();
      return await _inspect(reader);
    } finally {
      reader.close();
    }
  }

  Future<PdfLinearizationInfo> _inspect(PdfReader reader) async {
    final dictionary = await _findParameterDictionary(reader);
    if (dictionary == null) {
      return PdfLinearizationInfo(
        isLinearized: false,
        version: null,
        declaredFileLength: null,
        actualFileLength: bytes.length,
        hintStreamSpans: const <int>[],
        firstPageObjectNumber: null,
        endOfFirstPage: null,
        pageCount: null,
        mainXrefEntryOffset: null,
        firstPageNumber: 0,
        firstPageXrefOffset: null,
        mainXrefOffset: null,
        hintTables: null,
        problems: problems,
      );
    }

    final version =
        (await dictionary.numberEntry(PdfName('Linearized')))?.doubleValue();
    final declaredLength = await dictionary.integerEntry(PdfName('L'));
    final firstPageObject = await dictionary.integerEntry(PdfName('O'));
    final endOfFirstPage = await dictionary.integerEntry(PdfName('E'));
    final pageCount = await dictionary.integerEntry(PdfName('N'));
    final mainXrefEntry = await dictionary.integerEntry(PdfName('T'));
    final firstPageNumber = await dictionary.integerEntry(PdfName('P')) ?? 0;

    final spans = <int>[];
    final hintArray = await dictionary.arrayEntry(PdfName('H'));
    if (hintArray != null) {
      for (var i = 0; i < hintArray.size(); i++) {
        final value = await hintArray.numberEntry(i);
        if (value != null) spans.add(value.intValue());
      }
    }

    // --- Table F.1, the required entries -----------------------------------
    if (version == null) problems.add('/Linearized is missing.');
    for (final entry in <String, int?>{
      'L': declaredLength,
      'O': firstPageObject,
      'E': endOfFirstPage,
      'N': pageCount,
      'T': mainXrefEntry,
    }.entries) {
      if (entry.value == null) problems.add('/${entry.key} is missing.');
    }
    if (hintArray == null) {
      problems.add('/H is missing.');
    } else if (spans.length != 2 && spans.length != 4) {
      problems.add('/H shall hold two or four integers, not ${spans.length}.');
    }

    if (declaredLength != null && declaredLength != bytes.length) {
      problems.add('/L declares $declaredLength bytes but the file has '
          '${bytes.length}.');
    }

    // --- the hint stream ----------------------------------------------------
    PdfHintTables? tables;
    if (spans.length >= 2) {
      final offset = spans[0];
      final length = spans[1];
      if (offset < 0 || length <= 0 || offset + length > bytes.length) {
        problems.add('/H points outside the file.');
      } else {
        final header = _text(offset, 64);
        if (!RegExp(r'^\d+\s+\d+\s+obj').hasMatch(header)) {
          problems.add('/H does not point at an indirect object.');
        }
        try {
          tables = await _readHintTables(
              reader, offset, length, pageCount ?? 0, firstPageObject ?? 0);
        } on FormatException catch (error) {
          problems.add('The hint tables could not be read: ${error.message}');
        }
      }
    }

    // --- the two cross-reference sections -----------------------------------
    final firstPageXrefOffset = _finalStartxref();
    int? mainXrefOffset;
    if (firstPageXrefOffset == null) {
      problems.add('The file has no final startxref.');
    } else {
      final head = _text(firstPageXrefOffset, 5);
      if (!head.startsWith('xref') && !RegExp(r'^\d').hasMatch(head)) {
        problems.add('startxref does not point at the first-page '
            'cross-reference section.');
      }
      mainXrefOffset = await _firstPagePrev(reader, firstPageXrefOffset);
      if (mainXrefOffset == null) {
        problems.add('The first-page trailer has no /Prev pointing at the '
            'main cross-reference section (F.3.4).');
      } else if (mainXrefOffset < 0 || mainXrefOffset >= bytes.length) {
        problems.add('/Prev of the first-page trailer points outside the '
            'file.');
      }
    }

    if (mainXrefEntry != null && mainXrefOffset != null) {
      // F.3.3: /T is the white space before the entry for object 0, which for
      // a classic table sits just past "xref\n<first> <count>\n".
      if (mainXrefEntry <= mainXrefOffset ||
          mainXrefEntry > mainXrefOffset + 64) {
        problems.add('/T does not point just before the first entry of the '
            'main cross-reference table.');
      }
    }

    // --- page count and first page -----------------------------------------
    final actualPages = await reader.pageTotal();
    if (pageCount != null && actualPages > 0 && pageCount != actualPages) {
      problems.add('/N says $pageCount pages but the catalogue has '
          '$actualPages.');
    }
    if (firstPageObject != null) {
      final object = await reader.readObject(firstPageObject);
      final type = object is PdfDictionary
          ? await object.get(PdfName.type, false)
          : null;
      if (type != PdfName.page) {
        problems.add('/O does not name a page object.');
      }
    }
    if (endOfFirstPage != null &&
        (endOfFirstPage <= 0 || endOfFirstPage > bytes.length)) {
      problems.add('/E lies outside the file.');
    }

    return PdfLinearizationInfo(
      isLinearized: true,
      version: version,
      declaredFileLength: declaredLength,
      actualFileLength: bytes.length,
      hintStreamSpans: spans,
      firstPageObjectNumber: firstPageObject,
      endOfFirstPage: endOfFirstPage,
      pageCount: pageCount,
      mainXrefEntryOffset: mainXrefEntry,
      firstPageNumber: firstPageNumber,
      firstPageXrefOffset: firstPageXrefOffset,
      mainXrefOffset: mainXrefOffset,
      hintTables: tables,
      problems: problems,
    );
  }

  /// F.3.3: the dictionary is the first object of the body and lives entirely
  /// within the first 1024 bytes.
  Future<PdfDictionary?> _findParameterDictionary(PdfReader reader) async {
    final window = _text(0, PdfLinearizer._parameterDictionaryLimit);
    final match = RegExp(r'(\d+)\s+(\d+)\s+obj').firstMatch(window);
    if (match == null) return null;
    final number = int.parse(match.group(1)!);
    final object = await reader.readObject(number);
    if (object is! PdfDictionary) return null;
    if (!object.containsKey(PdfName('Linearized'))) return null;
    final end = window.indexOf('endobj', match.start);
    if (end < 0) {
      problems.add('The linearization parameter dictionary does not end '
          'within the first ${PdfLinearizer._parameterDictionaryLimit} bytes '
          'of the file (F.3.3).');
    }
    return object;
  }

  Future<int?> _firstPagePrev(PdfReader reader, int offset) async {
    final window = _text(offset, 4096);
    final trailer = window.indexOf('trailer');
    if (trailer < 0) return null;
    final match =
        RegExp(r'/Prev\s+(\d+)').firstMatch(window.substring(trailer));
    if (match == null) return null;
    return int.parse(match.group(1)!);
  }

  int? _finalStartxref() {
    final tail = _text(bytes.length - 2048 < 0 ? 0 : bytes.length - 2048, 2048);
    final matches = RegExp(r'startxref\s+(\d+)').allMatches(tail).toList();
    if (matches.isEmpty) return null;
    return int.parse(matches.last.group(1)!);
  }

  String _text(int offset, int length) {
    final start = offset < 0 ? 0 : offset;
    final end = start + length > bytes.length ? bytes.length : start + length;
    if (start >= end) return '';
    return String.fromCharCodes(bytes, start, end);
  }

  Future<PdfHintTables> _readHintTables(PdfReader reader, int offset,
      int length, int pageCount, int firstPageObject) async {
    // The hint stream is an ordinary indirect object with no references to it,
    // so find its number from the header at the given offset and read it.
    final header = _text(offset, 64);
    final match = RegExp(r'^(\d+)\s+\d+\s+obj').firstMatch(header);
    if (match == null) {
      throw const FormatException('the hint stream has no object header');
    }
    final object = await reader.readObject(int.parse(match.group(1)!));
    if (object is! PdfStream) {
      throw const FormatException('the hint stream is not a stream object');
    }
    final payload = await object.getBytes();
    if (payload == null) {
      throw const FormatException('the hint stream has no data');
    }
    final sharedOffset = await object.integerEntry(PdfName('S'));
    if (sharedOffset == null) {
      throw const FormatException('the required /S hint table is missing');
    }

    final reader1 = _BitReader(payload);
    final leastObjects = reader1.read(32);
    final firstPageOffset = reader1.read(32);
    final objectBits = reader1.read(16);
    final leastLength = reader1.read(32);
    final lengthBits = reader1.read(16);
    final leastContentOffset = reader1.read(32);
    final contentOffsetBits = reader1.read(16);
    final leastContentLength = reader1.read(32);
    final contentLengthBits = reader1.read(16);
    final sharedCountBits = reader1.read(16);
    final identifierBits = reader1.read(16);
    final fractionBits = reader1.read(16);
    final denominator = reader1.read(16);

    final pages = pageCount <= 0 ? 0 : pageCount;
    final objectCounts = <int>[
      for (var i = 0; i < pages; i++) leastObjects + reader1.read(objectBits)
    ];
    final pageLengths = <int>[
      for (var i = 0; i < pages; i++) leastLength + reader1.read(lengthBits)
    ];
    final sharedCounts = <int>[
      for (var i = 0; i < pages; i++) reader1.read(sharedCountBits)
    ];
    final identifiers = <List<int>>[const <int>[]];
    for (var i = 1; i < pages; i++) {
      identifiers.add(<int>[
        for (var j = 0; j < sharedCounts[i]; j++) reader1.read(identifierBits)
      ]);
    }
    final fractions = <List<int>>[const <int>[]];
    for (var i = 1; i < pages; i++) {
      fractions.add(<int>[
        for (var j = 0; j < sharedCounts[i]; j++) reader1.read(fractionBits)
      ]);
    }
    final contentOffsets = <int>[
      for (var i = 0; i < pages; i++)
        leastContentOffset + reader1.read(contentOffsetBits)
    ];
    final contentLengths = <int>[
      for (var i = 0; i < pages; i++)
        leastContentLength + reader1.read(contentLengthBits)
    ];

    // Page positions accumulate, with the hint stream skipped over (F.4).
    final pageOffsets = <int>[];
    var running = firstPageOffset;
    for (var i = 0; i < pages; i++) {
      pageOffsets.add(running);
      running += pageLengths[i];
    }

    final shared = _BitReader(payload, sharedOffset);
    final firstSharedNumber = shared.read(32);
    final firstSharedOffset = shared.read(32);
    final firstPageGroups = shared.read(32);
    final groupCount = shared.read(32);
    final groupObjectBits = shared.read(16);
    final leastGroupLength = shared.read(32);
    final groupLengthBits = shared.read(16);

    final groupLengths = <int>[
      for (var i = 0; i < groupCount; i++)
        leastGroupLength + shared.read(groupLengthBits)
    ];
    final signatures = <bool>[
      for (var i = 0; i < groupCount; i++) shared.read(1) == 1
    ];
    for (var i = 0; i < groupCount; i++) {
      if (signatures[i]) shared.read(128);
    }
    final groupObjects = <int>[
      for (var i = 0; i < groupCount; i++) shared.read(groupObjectBits) + 1
    ];

    return PdfHintTables(
      pages: <PdfPageHint>[
        for (var i = 0; i < pages; i++)
          PdfPageHint(
            objectCount: objectCounts[i],
            pageLength: pageLengths[i],
            pageOffset: pageOffsets[i],
            contentOffset: contentOffsets[i],
            contentLength: contentLengths[i],
            sharedIdentifiers: identifiers[i],
            sharedFractions: fractions[i],
          )
      ],
      leastObjectCount: leastObjects,
      firstPageObjectOffset: firstPageOffset,
      leastPageLength: leastLength,
      fractionDenominator: denominator,
      firstSharedObjectNumber: firstSharedNumber,
      firstSharedObjectOffset: firstSharedOffset,
      firstPageGroupCount: firstPageGroups,
      groups: <PdfSharedObjectGroup>[
        for (var i = 0; i < groupCount; i++)
          PdfSharedObjectGroup(
            objectCount: groupObjects[i],
            groupLength: groupLengths[i],
            hasSignature: signatures[i],
          )
      ],
    );
  }
}
