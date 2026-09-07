import 'dart:convert';
import 'dart:typed_data';

import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../kernel/pdf/reader_properties.dart';

/// How much a finding compromises the file.
///
/// [error] means a conforming reader may refuse the file or lose content.
/// [warning] means the file deviates from the specification but is usually
/// still readable. [info] records an observation, never a defect.
enum PdfIntegritySeverity { info, warning, error }

/// One observation about a document's structural health.
class PdfIntegrityFinding {
  /// Stable machine readable identifier, e.g. `missing-eof`. Message text may
  /// be reworded between releases; this code is the contract.
  final String code;

  final PdfIntegritySeverity severity;

  /// Human readable explanation, in English, of what was observed.
  final String message;

  /// Object number the finding belongs to, when it is object scoped.
  final int? objectNumber;

  /// Byte offset the finding refers to, when it is offset scoped.
  final int? offset;

  const PdfIntegrityFinding(
    this.code,
    this.severity,
    this.message, {
    this.objectNumber,
    this.offset,
  });

  @override
  String toString() {
    final where = objectNumber != null
        ? ' (object $objectNumber)'
        : offset != null
            ? ' (offset $offset)'
            : '';
    return '[${severity.name}] $code: $message$where';
  }
}

/// The result of inspecting one document.
///
/// A report is descriptive, never a repair: it says what a reader would find,
/// so a caller can decide whether to reject the file, re-request it, or open
/// it with [PdfRecoveryMode.scan].
class PdfIntegrityReport {
  /// False when the file could not be opened at all, even with recovery.
  final bool readable;

  /// True when the declared cross-reference sections were unusable and the
  /// objects had to be located by scanning the file.
  final bool recoveryUsed;

  /// True when the document declares an encryption dictionary.
  final bool encrypted;

  /// True when the supplied password did not open an encrypted document.
  final bool passwordRequired;

  /// Version from the `%PDF-` header, e.g. `1.7`; null when absent.
  final String? headerVersion;

  /// Version from the catalog's `/Version` entry, which overrides the header
  /// from PDF 1.4 onwards; null when absent.
  final String? catalogVersion;

  /// `/Count` declared by the page tree root; null when unreadable.
  final int? declaredPageCount;

  /// Page leaves actually reachable by walking the page tree.
  final int reachablePageCount;

  /// Entries in the cross-reference table, excluding free entries.
  final int objectCount;

  /// Number of `%%EOF` markers, i.e. one plus the incremental updates.
  final int revisionCount;

  /// Bytes after the last `%%EOF` marker.
  final int trailingBytes;

  final List<PdfIntegrityFinding> findings;

  const PdfIntegrityReport({
    required this.readable,
    required this.recoveryUsed,
    required this.encrypted,
    required this.passwordRequired,
    required this.headerVersion,
    required this.catalogVersion,
    required this.declaredPageCount,
    required this.reachablePageCount,
    required this.objectCount,
    required this.revisionCount,
    required this.trailingBytes,
    required this.findings,
  });

  /// True when at least one [PdfIntegritySeverity.error] was recorded.
  bool get isDamaged =>
      findings.any((f) => f.severity == PdfIntegritySeverity.error);

  /// True when nothing at all was recorded above [PdfIntegritySeverity.info].
  bool get isClean =>
      !findings.any((f) => f.severity != PdfIntegritySeverity.info);

  List<PdfIntegrityFinding> get errors => findings
      .where((f) => f.severity == PdfIntegritySeverity.error)
      .toList(growable: false);

  List<PdfIntegrityFinding> get warnings => findings
      .where((f) => f.severity == PdfIntegritySeverity.warning)
      .toList(growable: false);

  /// A stable, machine friendly view for logs and test fixtures.
  Map<String, Object?> toJson() => {
        'readable': readable,
        'recoveryUsed': recoveryUsed,
        'encrypted': encrypted,
        'passwordRequired': passwordRequired,
        'headerVersion': headerVersion,
        'catalogVersion': catalogVersion,
        'declaredPageCount': declaredPageCount,
        'reachablePageCount': reachablePageCount,
        'objectCount': objectCount,
        'revisionCount': revisionCount,
        'trailingBytes': trailingBytes,
        'damaged': isDamaged,
        'findings': [
          for (final f in findings)
            {
              'code': f.code,
              'severity': f.severity.name,
              'message': f.message,
              if (f.objectNumber != null) 'object': f.objectNumber,
              if (f.offset != null) 'offset': f.offset,
            }
        ],
      };

  @override
  String toString() {
    final buffer = StringBuffer('PdfIntegrityReport(')
      ..write(readable ? 'readable' : 'unreadable');
    if (isDamaged) buffer.write(', damaged');
    if (recoveryUsed) buffer.write(', recovered');
    buffer.write(', pages=$reachablePageCount');
    buffer.write(', objects=$objectCount');
    buffer.write(', findings=${findings.length})');
    return buffer.toString();
  }
}

/// Inspects a PDF's structure and reports what a reader would stumble on.
///
/// The checker never rewrites the input and never trusts a declared value it
/// can verify independently: page counts are walked, xref offsets are read
/// back, and stream lengths are measured against the file.
class PdfIntegrityChecker {
  PdfIntegrityChecker._();

  /// Bytes examined when looking for a header or a trailer marker.
  static const int _markerWindow = 4096;

  /// Inspects [bytes].
  ///
  /// [password] opens an encrypted document; without it an encrypted file is
  /// still reported, but only its lexical structure can be checked.
  ///
  /// [deepScan] additionally reads every object in the cross-reference table
  /// and decodes every page's content streams. It is the only way to detect a
  /// truncated or mis-filtered stream, and costs one full parse of the file.
  static Future<PdfIntegrityReport> inspect(
    Uint8List bytes, {
    String? password,
    bool deepScan = true,
  }) async {
    final findings = <PdfIntegrityFinding>[];

    final headerVersion = _checkHeader(bytes, findings);
    final revisionCount = _countMarkers(bytes, _eofMarker);
    final trailingBytes = _trailingBytes(bytes);
    _checkTrailerMarkers(bytes, revisionCount, trailingBytes, findings);

    var recoveryUsed = false;
    PdfDocument? document;
    PdfReader? reader;

    try {
      reader = _open(bytes, password, PdfRecoveryMode.strict);
      document = await PdfDocument.open(reader);
    } on Object catch (strictError) {
      if (_looksLikeBadPassword(strictError)) {
        return _unreadable(
          findings
            ..add(PdfIntegrityFinding(
              'password-required',
              PdfIntegritySeverity.error,
              'The document is encrypted and the supplied password did not '
                  'open it: $strictError',
            )),
          headerVersion: headerVersion,
          revisionCount: revisionCount,
          trailingBytes: trailingBytes,
          encrypted: true,
          passwordRequired: true,
        );
      }
      findings.add(PdfIntegrityFinding(
        'xref-unusable',
        PdfIntegritySeverity.error,
        'The declared cross-reference sections could not be read, so the '
            'objects had to be located by scanning: $strictError',
      ));
      try {
        reader = _open(bytes, password, PdfRecoveryMode.scan);
        document = await PdfDocument.open(reader);
        recoveryUsed = true;
      } on Object catch (scanError) {
        findings.add(PdfIntegrityFinding(
          'unreadable',
          PdfIntegritySeverity.error,
          'The document could not be opened even by scanning for objects: '
              '$scanError',
        ));
        return _unreadable(
          findings,
          headerVersion: headerVersion,
          revisionCount: revisionCount,
          trailingBytes: trailingBytes,
          encrypted: false,
          passwordRequired: false,
        );
      }
    }

    final encrypted = reader.securityCodec() != null;

    try {
      _checkStartXref(bytes, reader, findings);
      final catalogVersion = await _checkCatalog(document, findings);
      final objectCount = await _checkCrossReferences(
          bytes, document, reader, findings,
          deepScan: deepScan);
      final pages = await _walkPageTree(document, findings);

      if (pages.declared != null && pages.declared != pages.reachable) {
        findings.add(PdfIntegrityFinding(
          'page-count-mismatch',
          PdfIntegritySeverity.error,
          'The page tree declares /Count ${pages.declared} but '
              '${pages.reachable} page leaves are reachable.',
        ));
      }
      if (pages.reachable == 0) {
        findings.add(const PdfIntegrityFinding(
          'no-pages',
          PdfIntegritySeverity.error,
          'The document has no reachable page.',
        ));
      }

      if (deepScan && !encrypted) {
        await _checkPageContents(document, pages.reachable, findings);
      } else if (deepScan && encrypted) {
        findings.add(const PdfIntegrityFinding(
          'content-scan-skipped',
          PdfIntegritySeverity.info,
          'Page content streams were not decoded because the document is '
              'encrypted.',
        ));
      }

      return PdfIntegrityReport(
        readable: true,
        recoveryUsed: recoveryUsed,
        encrypted: encrypted,
        passwordRequired: false,
        headerVersion: headerVersion,
        catalogVersion: catalogVersion,
        declaredPageCount: pages.declared,
        reachablePageCount: pages.reachable,
        objectCount: objectCount,
        revisionCount: revisionCount,
        trailingBytes: trailingBytes,
        findings: List.unmodifiable(findings),
      );
    } finally {
      reader.close();
    }
  }

  static PdfReader _open(
      Uint8List bytes, String? password, PdfRecoveryMode mode) {
    final properties = ReaderProperties()..recoveryMode = mode;
    if (password != null) {
      properties.setPassword(Uint8List.fromList(utf8.encode(password)));
    }
    return PdfReader.fromBytes(bytes, properties);
  }

  static bool _looksLikeBadPassword(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('password') || text.contains('bad user');
  }

  static PdfIntegrityReport _unreadable(
    List<PdfIntegrityFinding> findings, {
    required String? headerVersion,
    required int revisionCount,
    required int trailingBytes,
    required bool encrypted,
    required bool passwordRequired,
  }) {
    return PdfIntegrityReport(
      readable: false,
      recoveryUsed: false,
      encrypted: encrypted,
      passwordRequired: passwordRequired,
      headerVersion: headerVersion,
      catalogVersion: null,
      declaredPageCount: null,
      reachablePageCount: 0,
      objectCount: 0,
      revisionCount: revisionCount,
      trailingBytes: trailingBytes,
      findings: List.unmodifiable(findings),
    );
  }

  // --- lexical checks -------------------------------------------------------

  static final RegExp _headerPattern =
      RegExp(r'%PDF-([0-9]+)\.([0-9]+)(?=[\r\n\t ]|$)');

  static const List<int> _eofMarker = [0x25, 0x25, 0x45, 0x4F, 0x46]; // %%EOF

  static String? _checkHeader(
      Uint8List bytes, List<PdfIntegrityFinding> findings) {
    if (bytes.isEmpty) {
      findings.add(const PdfIntegrityFinding(
        'empty-file',
        PdfIntegritySeverity.error,
        'The input has no bytes.',
      ));
      return null;
    }
    final window = bytes.length < _markerWindow ? bytes.length : _markerWindow;
    final prefix = latin1.decode(bytes.sublist(0, window), allowInvalid: true);
    final match = _headerPattern.firstMatch(prefix);
    if (match == null) {
      findings.add(const PdfIntegrityFinding(
        'missing-header',
        PdfIntegritySeverity.error,
        'No %PDF- header was found in the first $_markerWindow bytes.',
      ));
      return null;
    }
    if (match.start != 0) {
      findings.add(PdfIntegrityFinding(
        'header-not-at-start',
        PdfIntegritySeverity.warning,
        'The %PDF- header starts at offset ${match.start} instead of 0; all '
            'byte offsets in the file are shifted by that amount.',
        offset: match.start,
      ));
    }
    return '${match.group(1)}.${match.group(2)}';
  }

  static void _checkTrailerMarkers(
    Uint8List bytes,
    int revisionCount,
    int trailingBytes,
    List<PdfIntegrityFinding> findings,
  ) {
    if (revisionCount == 0) {
      findings.add(const PdfIntegrityFinding(
        'missing-eof',
        PdfIntegritySeverity.error,
        'The file has no %%EOF marker, which usually means it was truncated '
            'during transfer.',
      ));
      return;
    }
    if (trailingBytes > 0) {
      findings.add(PdfIntegrityFinding(
        'trailing-bytes',
        PdfIntegritySeverity.warning,
        '$trailingBytes bytes follow the last %%EOF marker.',
        offset: bytes.length - trailingBytes,
      ));
    }
    if (revisionCount > 1) {
      findings.add(PdfIntegrityFinding(
        'incremental-updates',
        PdfIntegritySeverity.info,
        'The file carries ${revisionCount - 1} incremental update(s) after the '
            'original revision.',
      ));
    }
  }

  static void _checkStartXref(
    Uint8List bytes,
    PdfReader reader,
    List<PdfIntegrityFinding> findings,
  ) {
    final position = reader.getLastXrefPosition();
    if (position <= 0 || position >= bytes.length) {
      findings.add(PdfIntegrityFinding(
        'startxref-out-of-range',
        PdfIntegritySeverity.error,
        'startxref points to offset $position, outside the ${bytes.length} '
            'byte file.',
        offset: position,
      ));
    }
  }

  static int _countMarkers(Uint8List bytes, List<int> marker) {
    var count = 0;
    final limit = bytes.length - marker.length;
    for (var i = 0; i <= limit; i++) {
      var hit = true;
      for (var j = 0; j < marker.length; j++) {
        if (bytes[i + j] != marker[j]) {
          hit = false;
          break;
        }
      }
      if (hit) {
        count++;
        i += marker.length - 1;
      }
    }
    return count;
  }

  static int _trailingBytes(Uint8List bytes) {
    for (var i = bytes.length - _eofMarker.length; i >= 0; i--) {
      var hit = true;
      for (var j = 0; j < _eofMarker.length; j++) {
        if (bytes[i + j] != _eofMarker[j]) {
          hit = false;
          break;
        }
      }
      if (hit) {
        var end = i + _eofMarker.length;
        // A single trailing EOL after %%EOF is what writers emit; it is not
        // garbage.
        while (
            end < bytes.length && (bytes[end] == 0x0D || bytes[end] == 0x0A)) {
          end++;
        }
        return bytes.length - end;
      }
    }
    return 0;
  }

  // --- structural checks ----------------------------------------------------

  static Future<String?> _checkCatalog(
    PdfDocument document,
    List<PdfIntegrityFinding> findings,
  ) async {
    final trailer = document.fileTrailer();
    if (!trailer.containsKey(PdfName.root)) {
      findings.add(const PdfIntegrityFinding(
        'missing-root',
        PdfIntegritySeverity.error,
        'The trailer has no /Root entry, so no catalog can be located.',
      ));
      return null;
    }

    final catalog = document.rootCatalog().pdfRepresentation();
    final type = await catalog.nameEntry(PdfName.type);
    if (type == null) {
      findings.add(const PdfIntegrityFinding(
        'catalog-untyped',
        PdfIntegritySeverity.warning,
        'The catalog has no /Type entry; /Type /Catalog is required.',
      ));
    } else if (type.getValue() != 'Catalog') {
      findings.add(PdfIntegrityFinding(
        'catalog-wrong-type',
        PdfIntegritySeverity.error,
        'The object referenced by /Root has /Type /${type.getValue()} instead '
            'of /Catalog.',
      ));
    }

    final version = await catalog.nameEntry(PdfName('Version'));
    return version?.getValue();
  }

  static Future<int> _checkCrossReferences(
    Uint8List bytes,
    PdfDocument document,
    PdfReader reader,
    List<PdfIntegrityFinding> findings, {
    required bool deepScan,
  }) async {
    final xref = document.crossReferenceTable();
    var live = 0;
    var offsetErrors = 0;
    var parseErrors = 0;

    for (var objectNumber = 1; objectNumber < xref.size(); objectNumber++) {
      final reference = xref.get(objectNumber);
      if (reference == null || reference.isFree()) continue;
      live++;

      if (reference.getObjStreamNumber() == 0) {
        final offset = reference.getOffset();
        if (offset <= 0 || offset >= bytes.length) {
          if (offsetErrors++ < _reportLimit) {
            findings.add(PdfIntegrityFinding(
              'xref-offset-out-of-range',
              PdfIntegritySeverity.error,
              'The cross-reference entry points to offset $offset, outside the '
                  '${bytes.length} byte file.',
              objectNumber: objectNumber,
              offset: offset,
            ));
          }
          continue;
        }
        if (!_startsWithObjectHeader(bytes, offset, objectNumber)) {
          if (offsetErrors++ < _reportLimit) {
            findings.add(PdfIntegrityFinding(
              'xref-offset-mismatch',
              PdfIntegritySeverity.error,
              'Offset $offset does not begin the definition of object '
                  '$objectNumber.',
              objectNumber: objectNumber,
              offset: offset,
            ));
          }
          continue;
        }
      }

      if (!deepScan) continue;
      try {
        final object = await reader.readObject(objectNumber);
        if (object == null) {
          if (parseErrors++ < _reportLimit) {
            findings.add(PdfIntegrityFinding(
              'object-unreadable',
              PdfIntegritySeverity.error,
              'Object $objectNumber is listed as in use but resolves to '
                  'nothing.',
              objectNumber: objectNumber,
            ));
          }
        } else if (object.objectKind() == PdfObjectType.stream) {
          await _checkStream(object as PdfStream, objectNumber, findings);
        }
      } on Object catch (error) {
        if (parseErrors++ < _reportLimit) {
          findings.add(PdfIntegrityFinding(
            'object-parse-failed',
            PdfIntegritySeverity.error,
            'Object $objectNumber could not be parsed: $error',
            objectNumber: objectNumber,
          ));
        }
      }
    }

    _summarize(findings, offsetErrors, 'xref-offset');
    _summarize(findings, parseErrors, 'object-parse');
    return live;
  }

  static const int _reportLimit = 25;

  static void _summarize(
      List<PdfIntegrityFinding> findings, int total, String kind) {
    if (total > _reportLimit) {
      findings.add(PdfIntegrityFinding(
        '$kind-truncated',
        PdfIntegritySeverity.info,
        '$total findings of this kind were detected; only the first '
            '$_reportLimit are listed.',
      ));
    }
  }

  static Future<void> _checkStream(
    PdfStream stream,
    int objectNumber,
    List<PdfIntegrityFinding> findings,
  ) async {
    try {
      final raw = await stream.getRawBytes();
      final declared = await stream.integerEntry(PdfName.length);
      if (raw != null && declared != null && declared != raw.length) {
        findings.add(PdfIntegrityFinding(
          'stream-length-mismatch',
          PdfIntegritySeverity.warning,
          'The stream declares /Length $declared but ${raw.length} bytes were '
              'read before endstream.',
          objectNumber: objectNumber,
        ));
      }
      await stream.getBytes();
    } on Object catch (error) {
      findings.add(PdfIntegrityFinding(
        'stream-decode-failed',
        PdfIntegritySeverity.error,
        'The stream of object $objectNumber could not be decoded: $error',
        objectNumber: objectNumber,
      ));
    }
  }

  static bool _startsWithObjectHeader(
      Uint8List bytes, int offset, int objectNumber) {
    var i = offset;
    while (i < bytes.length && _isWhitespace(bytes[i])) {
      i++;
    }
    final digits = objectNumber.toString().codeUnits;
    if (i + digits.length > bytes.length) return false;
    for (var j = 0; j < digits.length; j++) {
      if (bytes[i + j] != digits[j]) return false;
    }
    i += digits.length;
    if (i >= bytes.length || !_isWhitespace(bytes[i])) return false;
    while (i < bytes.length && _isWhitespace(bytes[i])) {
      i++;
    }
    // Generation number.
    var sawDigit = false;
    while (i < bytes.length && bytes[i] >= 0x30 && bytes[i] <= 0x39) {
      i++;
      sawDigit = true;
    }
    if (!sawDigit) return false;
    while (i < bytes.length && _isWhitespace(bytes[i])) {
      i++;
    }
    return i + 3 <= bytes.length &&
        bytes[i] == 0x6F && // o
        bytes[i + 1] == 0x62 && // b
        bytes[i + 2] == 0x6A; // j
  }

  static bool _isWhitespace(int byte) =>
      byte == 0x00 ||
      byte == 0x09 ||
      byte == 0x0A ||
      byte == 0x0C ||
      byte == 0x0D ||
      byte == 0x20;

  // --- page tree ------------------------------------------------------------

  static Future<_PageWalk> _walkPageTree(
    PdfDocument document,
    List<PdfIntegrityFinding> findings,
  ) async {
    final catalog = document.rootCatalog().pdfRepresentation();
    final root = await catalog.dictionaryEntry(PdfName.pages);
    if (root == null) {
      findings.add(const PdfIntegrityFinding(
        'missing-page-tree',
        PdfIntegritySeverity.error,
        'The catalog has no readable /Pages entry.',
      ));
      return const _PageWalk(null, 0);
    }
    final declared = await root.integerEntry(PdfName.count);
    final seen = <PdfDictionary>{};
    final reachable = await _countLeaves(root, seen, findings, 0);
    return _PageWalk(declared, reachable);
  }

  static const int _maxPageTreeDepth = 64;

  static Future<int> _countLeaves(
    PdfDictionary node,
    Set<PdfDictionary> seen,
    List<PdfIntegrityFinding> findings,
    int depth,
  ) async {
    if (depth > _maxPageTreeDepth) {
      findings.add(const PdfIntegrityFinding(
        'page-tree-too-deep',
        PdfIntegritySeverity.error,
        'The page tree is nested deeper than $_maxPageTreeDepth levels, which '
            'a reader treats as malformed.',
      ));
      return 0;
    }
    if (!seen.add(node)) {
      findings.add(const PdfIntegrityFinding(
        'page-tree-cycle',
        PdfIntegritySeverity.error,
        'The page tree contains a cycle; the same node is reachable twice.',
      ));
      return 0;
    }

    final PdfArray? kids = await node.arrayEntry(PdfName.kids);
    if (kids == null) {
      // A node without /Kids is a leaf. /Type is advisory here because damaged
      // files often drop it, and a reader still renders the page.
      return 1;
    }

    var total = 0;
    for (var i = 0; i < kids.size(); i++) {
      PdfDictionary? kid;
      try {
        kid = await kids.dictionaryEntry(i);
      } on Object catch (error) {
        findings.add(PdfIntegrityFinding(
          'page-kid-unreadable',
          PdfIntegritySeverity.error,
          'Entry $i of a /Kids array could not be resolved: $error',
        ));
        continue;
      }
      if (kid == null) {
        findings.add(PdfIntegrityFinding(
          'page-kid-missing',
          PdfIntegritySeverity.error,
          'Entry $i of a /Kids array does not resolve to a dictionary.',
        ));
        continue;
      }
      total += await _countLeaves(kid, seen, findings, depth + 1);
    }
    return total;
  }

  static Future<void> _checkPageContents(
    PdfDocument document,
    int pageCount,
    List<PdfIntegrityFinding> findings,
  ) async {
    var failures = 0;
    for (var pageNumber = 1; pageNumber <= pageCount; pageNumber++) {
      try {
        final page = await document.pageAt(pageNumber);
        if (page == null) {
          findings.add(PdfIntegrityFinding(
            'page-unreachable',
            PdfIntegritySeverity.error,
            'Page $pageNumber is counted by the page tree but cannot be '
                'loaded.',
          ));
          continue;
        }
        await page.contentPayload();
        await page.mediaBounds();
      } on Object catch (error) {
        if (failures++ < _reportLimit) {
          findings.add(PdfIntegrityFinding(
            'page-content-failed',
            PdfIntegritySeverity.error,
            'The content of page $pageNumber could not be assembled: $error',
          ));
        }
      }
    }
    _summarize(findings, failures, 'page-content');
  }
}

class _PageWalk {
  final int? declared;
  final int reachable;
  const _PageWalk(this.declared, this.reachable);
}
