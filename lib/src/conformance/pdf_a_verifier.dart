import 'dart:convert';
import 'dart:typed_data';

import '../io/colors/icc_profile.dart';
import '../kernel/font/unicode_code_map.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_page.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../kernel/pdf/pdf_version.dart';
import '../kernel/pdf/reader_properties.dart';
import 'content_stream_scan.dart';
import 'finding_sink.dart';
import 'pdf_conformance.dart';
import 'pdf_conformance_report.dart';
import 'structure_scan.dart';
import 'xmp_identification.dart';

/// Checks an existing document against a PDF/A profile.
///
/// The verifier reads; it never rewrites the input. It decides the rules that
/// can be settled from the file itself: metadata and its agreement with the
/// document information dictionary, the output intent and the ICC profile it
/// names, font embedding and the metrics and Unicode maps that go with it, the
/// colour spaces the content streams actually select, encryption, forbidden
/// actions and annotations, transparency, filters, and — at the accessible
/// levels — the shape of the structure tree.
///
/// What is left is listed in [PdfConformanceReport.unverifiedRules] rather
/// than silently passed, because a clean report that hid a rule would be worse
/// than no report at all.
class PdfAVerifier {
  PdfAVerifier._();

  /// Verifies [bytes] against [level].
  ///
  /// When [level] is null the profile declared by the document's own XMP
  /// metadata is used; a document that declares none is reported as such and
  /// no further rule is applied.
  static Future<PdfConformanceReport> verify(
    Uint8List bytes, {
    PdfAConformanceLevel? level,
    String? password,
  }) async {
    final findings = FindingSink();
    final properties = ReaderProperties();
    if (password != null) {
      properties.setPassword(Uint8List.fromList(utf8.encode(password)));
    }

    final reader = PdfReader.fromBytes(bytes, properties);
    final document = await PdfDocument.open(reader);
    try {
      final catalog = document.rootCatalog().pdfRepresentation();
      final claim = await XmpIdentification.read(catalog);
      final claimed = claim.pdfALevel;

      final target = level ?? claimed;
      if (target == null) {
        findings.add(const PdfConformanceFinding(
          'no-declared-profile',
          PdfConformanceSeverity.violation,
          'The document declares no pdfaid:part in its XMP metadata, so it '
              'claims no PDF/A profile. Pass an explicit level to check it '
              'against one anyway.',
          clause: 'ISO 19005-1:6.7.11',
        ));
        return PdfConformanceReport(
          profile: 'unknown',
          claimedProfile: null,
          findings: findings.build(),
          unverifiedRules: const [],
        );
      }

      if (claimed != null && claimed != target) {
        findings.add(PdfConformanceFinding(
          'profile-mismatch',
          PdfConformanceSeverity.warning,
          'The document declares ${claimed.label} but is being checked against '
              '${target.label}.',
          clause: 'ISO 19005-1:6.7.11',
        ));
      } else if (claimed == null) {
        findings.add(PdfConformanceFinding(
          'missing-pdfaid',
          PdfConformanceSeverity.violation,
          'The XMP metadata does not identify the file as ${target.label}; '
              'pdfaid:part is required.',
          clause: 'ISO 19005-1:6.7.11',
        ));
      }

      await _checkVersion(document, target, findings);
      await _checkEncryption(document, findings);
      await _checkMetadata(catalog, findings);
      final intentSpace = await _checkOutputIntents(catalog, target, findings);
      await _checkCatalogEntries(catalog, target, findings);
      await _checkEmbeddedFiles(catalog, target, findings);
      await _checkXmp(document, claim, target, findings);
      await _checkTagging(catalog, target, findings);
      await _checkPages(document, target, intentSpace, findings);
      await _checkObjects(document, target, findings);

      return PdfConformanceReport(
        profile: target.label,
        claimedProfile: claimed?.label,
        findings: findings.build(),
        unverifiedRules: List.unmodifiable(_unverified(target)),
      );
    } finally {
      reader.close();
    }
  }

  /// The rules this verifier does not settle, each with the reason it cannot.
  ///
  /// Every entry here needs something the object graph does not contain: the
  /// decoded glyph table of an embedded font program, or a judgement about
  /// what the page looks like. A rule that can be decided from the file is
  /// implemented above instead of being listed here.
  static List<String> _unverified(PdfAConformanceLevel level) => [
        // Deciding this means decoding the embedded CFF, TrueType or Type 1
        // program and mapping each code through the font's encoding to a
        // glyph — a font rasteriser's job, not a validator's.
        'Glyph presence: whether every code drawn exists as a glyph in the '
            'embedded font program. Font embedding, /Widths consistency and '
            'the presence and coverage of /ToUnicode are checked; the glyph '
            'table inside the font program is not opened.',
        if (level.requiresTagging)
          // Reading order is the order a person would read the page in. Only
          // rendering the page and judging the result can decide it.
          'Whether the reading order recorded in the structure tree matches '
              'the order a reader would follow on the rendered page. The '
              'shape of the tree — heading nesting, table geometry, list '
              'composition, role mapping — is checked.',
      ];

  // --- document wide --------------------------------------------------------

  static Future<void> _checkVersion(
    PdfDocument document,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final version = (document.formatVersion() ?? PdfVersion.PDF_1_7)
        .toString()
        .replaceFirst('PDF-', '');
    final maximum = level.maximumPdfVersion;
    if (_compareVersions(version, maximum) > 0) {
      findings.add(PdfConformanceFinding(
        'version-too-high',
        PdfConformanceSeverity.violation,
        'The document declares PDF $version but ${level.label} is limited to '
            'PDF $maximum.',
        clause: 'ISO 19005-${level.part}:6.1.2',
      ));
    }
  }

  static int _compareVersions(String a, String b) {
    final left = a.split('.');
    final right = b.split('.');
    for (var i = 0; i < 2; i++) {
      final l = i < left.length ? int.tryParse(left[i]) ?? 0 : 0;
      final r = i < right.length ? int.tryParse(right[i]) ?? 0 : 0;
      if (l != r) return l - r;
    }
    return 0;
  }

  static Future<void> _checkEncryption(
    PdfDocument document,
    FindingSink findings,
  ) async {
    if (document.fileTrailer().containsKey(PdfName.encrypt)) {
      findings.add(const PdfConformanceFinding(
        'encrypted',
        PdfConformanceSeverity.violation,
        'The trailer carries an /Encrypt dictionary. A PDF/A file must not be '
            'encrypted, because a future reader could not open it.',
        clause: 'ISO 19005-1:6.1.3',
      ));
    }
  }

  static Future<void> _checkMetadata(
    PdfDictionary catalog,
    FindingSink findings,
  ) async {
    if (!catalog.containsKey(PdfName.metadata)) {
      findings.add(const PdfConformanceFinding(
        'missing-metadata',
        PdfConformanceSeverity.violation,
        'The catalog has no /Metadata entry; PDF/A identification lives in an '
            'XMP packet there.',
        clause: 'ISO 19005-1:6.7.2',
      ));
      return;
    }
    final stream = await catalog.streamEntry(PdfName.metadata);
    if (stream == null) {
      findings.add(const PdfConformanceFinding(
        'metadata-not-a-stream',
        PdfConformanceSeverity.violation,
        'The catalog /Metadata entry does not resolve to a stream.',
        clause: 'ISO 19005-1:6.7.2',
      ));
      return;
    }
    if (stream.containsKey(PdfName.filter)) {
      findings.add(const PdfConformanceFinding(
        'metadata-filtered',
        PdfConformanceSeverity.violation,
        'The XMP metadata stream is filtered. It must be stored uncompressed '
            'so a reader can find the packet without decoding the file.',
        clause: 'ISO 19005-1:6.7.2',
      ));
    }
  }

  // --- output intent and its ICC profile ------------------------------------

  /// Checks the output intents and returns the ICC data colour space the
  /// PDF/A intent declares, e.g. `RGB ` or `CMYK`.
  ///
  /// That value is what decides whether a device colour operator on a page is
  /// legal, so the colour rules below depend on this one running first.
  static Future<String?> _checkOutputIntents(
    PdfDictionary catalog,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final intents = await catalog.arrayEntry(PdfName('OutputIntents'));
    if (intents == null || intents.size() == 0) {
      findings.add(PdfConformanceFinding(
        'missing-output-intent',
        PdfConformanceSeverity.violation,
        'The catalog declares no /OutputIntents. A PDF/A file that uses '
            'device colour needs one to define what those values mean.',
        clause: 'ISO 19005-${level.part}:6.2.2',
      ));
      return null;
    }

    var seenPdfA = false;
    String? colourSpace;
    PdfObject? firstProfile;
    for (var i = 0; i < intents.size(); i++) {
      final intent = await intents.dictionaryEntry(i);
      if (intent == null) continue;
      final subtype = await intent.nameEntry(PdfName('S'));
      if (subtype?.getValue() == 'GTS_PDFA1') {
        seenPdfA = true;
        final profile = await intent.get(PdfName('DestOutputProfile'));
        if (profile == null) {
          findings.add(PdfConformanceFinding(
            'output-intent-without-profile',
            PdfConformanceSeverity.violation,
            'The GTS_PDFA1 output intent has no /DestOutputProfile, so the '
                'colour space it names cannot be resolved.',
            clause: 'ISO 19005-${level.part}:6.2.2',
          ));
        } else {
          firstProfile ??= profile;
          if (!identical(firstProfile, profile)) {
            findings.add(PdfConformanceFinding(
              'output-intent-profiles-differ',
              PdfConformanceSeverity.violation,
              'Several output intents carry different /DestOutputProfile '
                  'objects; they must all reference the same one.',
              clause: 'ISO 19005-${level.part}:6.2.2',
            ));
          }
          colourSpace ??= await _checkDestOutputProfile(
              await intent.streamEntry(PdfName('DestOutputProfile')),
              level,
              findings);
        }
        if (!intent.containsKey(PdfName('OutputConditionIdentifier'))) {
          findings.add(PdfConformanceFinding(
            'output-intent-unidentified',
            PdfConformanceSeverity.violation,
            'The GTS_PDFA1 output intent has no /OutputConditionIdentifier.',
            clause: 'ISO 19005-${level.part}:6.2.2',
          ));
        }
      }
    }
    if (!seenPdfA) {
      findings.add(PdfConformanceFinding(
        'no-pdfa-output-intent',
        PdfConformanceSeverity.violation,
        'None of the output intents has /S /GTS_PDFA1.',
        clause: 'ISO 19005-${level.part}:6.2.2',
      ));
    }
    return colourSpace;
  }

  /// Reads the ICC profile header and reports what is wrong with it.
  ///
  /// Returns the data colour space the profile declares, which is what the
  /// device colour rules are measured against, or null when the profile
  /// cannot be read at all.
  static Future<String?> _checkDestOutputProfile(
    PdfStream? profile,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    if (profile == null) {
      findings.add(PdfConformanceFinding(
        'output-profile-not-a-stream',
        PdfConformanceSeverity.violation,
        'The /DestOutputProfile is not a stream, so it carries no ICC '
            'profile.',
        clause: 'ISO 19005-${level.part}:6.2.2',
      ));
      return null;
    }

    Uint8List? data;
    try {
      data = await profile.getBytes();
    } on Object {
      data = null;
    }
    if (data == null || data.length < 128) {
      findings.add(PdfConformanceFinding(
        'output-profile-truncated',
        PdfConformanceSeverity.violation,
        'The /DestOutputProfile holds ${data?.length ?? 0} bytes; an ICC '
            'profile starts with a 128 byte header.',
        clause: 'ISO 19005-${level.part}:6.2.2',
      ));
      return null;
    }
    if (!IccProfileHeader.hasSignature(data)) {
      findings.add(PdfConformanceFinding(
        'output-profile-not-icc',
        PdfConformanceSeverity.violation,
        'The /DestOutputProfile does not carry the "acsp" signature ICC '
            'requires at offset 36, so it is not an ICC profile.',
        clause: 'ISO 19005-${level.part}:6.2.2',
      ));
      return null;
    }

    final header = IccProfileHeader.parse(data)!;
    for (final defect in header.defects()) {
      findings.add(PdfConformanceFinding(
        'output-profile-invalid',
        PdfConformanceSeverity.violation,
        'The ICC profile in /DestOutputProfile is not usable: $defect.',
        clause: 'ISO 19005-${level.part}:6.2.2',
      ));
    }

    // ISO 19005-1 is built on PDF 1.4, whose ICC support stops at version 2;
    // the later parts follow PDF 1.7 and PDF 2.0 and accept version 4.
    if (level.part == '1' && header.majorVersion > 2) {
      findings.add(PdfConformanceFinding(
        'output-profile-version',
        PdfConformanceSeverity.violation,
        'The ICC profile declares version ${header.majorVersion}.'
            '${header.minorVersion}; ${level.label} is built on PDF 1.4, '
            'which only defines ICC version 2 profiles.',
        clause: 'ISO 19005-1:6.2.2',
      ));
    }

    final declared = await profile.integerEntry(PdfName.n);
    final expected = header.numberOfComponents;
    if (declared != null && expected != null && declared != expected) {
      findings.add(PdfConformanceFinding(
        'output-profile-component-count',
        PdfConformanceSeverity.violation,
        'The /DestOutputProfile stream declares /N $declared but its ICC '
            'colour space "${header.colourSpace}" has $expected components.',
        clause: 'ISO 19005-${level.part}:6.2.2',
      ));
    }
    return header.colourSpace;
  }

  // --- catalog --------------------------------------------------------------

  /// Entries a PDF/A catalog must not carry, with the clause that forbids them.
  static const Map<String, String> _forbiddenCatalogEntries = {
    'AA': 'a catalog must not declare additional actions',
    'OCProperties': 'optional content is not permitted',
  };

  static Future<void> _checkCatalogEntries(
    PdfDictionary catalog,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    for (final entry in _forbiddenCatalogEntries.entries) {
      // Optional content arrived with PDF 1.5 and is allowed from PDF/A-2 on.
      if (entry.key == 'OCProperties' && level.part != '1') continue;
      if (catalog.containsKey(PdfName(entry.key))) {
        findings.add(PdfConformanceFinding(
          'catalog-${entry.key.toLowerCase()}',
          PdfConformanceSeverity.violation,
          'The catalog contains /${entry.key}: ${entry.value}.',
          clause: 'ISO 19005-${level.part}:6.6.2',
        ));
      }
    }

    final names = await catalog.dictionaryEntry(PdfName('Names'));
    if (names != null) {
      if (names.containsKey(PdfName('JavaScript'))) {
        findings.add(PdfConformanceFinding(
          'catalog-javascript',
          PdfConformanceSeverity.violation,
          'The name dictionary contains /JavaScript. A PDF/A file must not '
              'carry executable content.',
          clause: 'ISO 19005-${level.part}:6.6.1',
        ));
      }
      if (!level.allowsEmbeddedFiles &&
          names.containsKey(PdfName('EmbeddedFiles'))) {
        findings.add(PdfConformanceFinding(
          'catalog-embedded-files',
          PdfConformanceSeverity.violation,
          'The name dictionary contains /EmbeddedFiles, which ${level.label} '
              'does not permit.',
          clause: 'ISO 19005-${level.part}:6.1.11',
        ));
      }
    }

    await _checkAcroForm(catalog, level, findings);

    final openAction = await catalog.get(PdfName('OpenAction'));
    if (openAction != null &&
        openAction.objectKind() == PdfObjectType.dictionary) {
      await _checkAction(openAction as PdfDictionary, level, findings);
    }
  }

  static Future<void> _checkAcroForm(
    PdfDictionary catalog,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final form = await catalog.dictionaryEntry(PdfName.acroForm);
    if (form == null) return;

    if (form.containsKey(PdfName('XFA'))) {
      findings.add(PdfConformanceFinding(
        'acroform-xfa',
        PdfConformanceSeverity.violation,
        'The interactive form carries an /XFA entry. An XFA form is an XML '
            'application the PDF only hosts, so the appearance of the file '
            'would depend on software outside it.',
        clause: 'ISO 19005-${level.part}:6.6.1',
      ));
    }
    if (await form.flagEntry(PdfName('NeedAppearances')) == true) {
      findings.add(PdfConformanceFinding(
        'acroform-needappearances',
        PdfConformanceSeverity.violation,
        'The interactive form sets /NeedAppearances true, which asks the '
            'reader to generate the field appearances rather than storing '
            'them.',
        clause: 'ISO 19005-${level.part}:6.6.1',
      ));
    }
  }

  /// Embedded files: forbidden outright before PDF/A-3, and from PDF/A-3 on
  /// permitted only when each one says how it relates to the document.
  static Future<void> _checkEmbeddedFiles(
    PdfDictionary catalog,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    if (!level.allowsEmbeddedFiles) return;

    final names = await catalog.dictionaryEntry(PdfName('Names'));
    final tree = await names?.dictionaryEntry(PdfName('EmbeddedFiles'));
    if (tree == null) return;

    for (final specification in await _fileSpecifications(tree, 0)) {
      if (!specification.containsKey(PdfName('AFRelationship'))) {
        findings.add(PdfConformanceFinding(
          'embedded-file-without-relationship',
          PdfConformanceSeverity.violation,
          'An embedded file has no /AFRelationship, so nothing says whether '
              'it is the source of the document, its data, or an unrelated '
              'attachment. ${level.label} permits attachments only when they '
              'declare that.',
          clause: 'ISO 19005-3:6.8',
        ));
      }
    }
  }

  /// Walks a name tree of file specifications, through its /Kids.
  static Future<List<PdfDictionary>> _fileSpecifications(
    PdfDictionary node,
    int depth,
  ) async {
    if (depth > 32) return const [];
    final result = <PdfDictionary>[];

    final values = await node.arrayEntry(PdfName('Names'));
    if (values != null) {
      for (var i = 1; i < values.size(); i += 2) {
        final specification = await values.dictionaryEntry(i);
        if (specification != null) result.add(specification);
      }
    }
    final kids = await node.arrayEntry(PdfName('Kids'));
    if (kids != null) {
      for (var i = 0; i < kids.size(); i++) {
        final kid = await kids.dictionaryEntry(i);
        if (kid != null) {
          result.addAll(await _fileSpecifications(kid, depth + 1));
        }
      }
    }
    return result;
  }

  // --- XMP ------------------------------------------------------------------

  /// Document information entries and the XMP properties that must agree with
  /// them, per ISO 19005-1 6.7.3.
  static const Map<String, String> _infoToXmp = {
    'Title': 'dc:title',
    'Author': 'dc:creator',
    'Subject': 'dc:description',
    'Keywords': 'pdf:Keywords',
    'Creator': 'xmp:CreatorTool',
    'Producer': 'pdf:Producer',
    'CreationDate': 'xmp:CreateDate',
    'ModDate': 'xmp:ModifyDate',
  };

  static Future<void> _checkXmp(
    PdfDocument document,
    XmpIdentification claim,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    if (!claim.present) return;

    if (claim.pdfAPart != null && claim.pdfALevel == null) {
      findings.add(PdfConformanceFinding(
        'unknown-pdfaid',
        PdfConformanceSeverity.violation,
        'The XMP metadata declares pdfaid:part ${claim.pdfAPart} with '
            'conformance ${claim.pdfAConformance ?? "(none)"}, which is not a '
            'profile ISO 19005 defines.',
        clause: 'ISO 19005-${level.part}:6.7.11',
      ));
    }

    for (final namespace in claim.propertyNamespaces) {
      if (XmpIdentification.predefinedNamespaces.contains(namespace)) continue;
      if (claim.extensionNamespaces.contains(namespace)) continue;
      findings.add(PdfConformanceFinding(
        'xmp-extension-schema-missing',
        PdfConformanceSeverity.violation,
        'The XMP packet carries properties in the namespace $namespace, which '
            'is not one of the predefined schemas, and declares no PDF/A '
            'extension schema for it. A later reader would have no way to '
            'learn what those properties mean.',
        clause: 'ISO 19005-${level.part}:6.7.9',
      ));
    }

    final info = await document.fileTrailer().dictionaryEntry(PdfName.info);
    if (info == null) return;
    final xmpValues = <String, String?>{
      'Title': claim.title,
      'Author': claim.creator,
      'Subject': claim.description,
      'Keywords': claim.keywords,
      'Creator': claim.creatorTool,
      'Producer': claim.producer,
      'CreationDate': claim.createDate,
      'ModDate': claim.modifyDate,
    };

    for (final entry in _infoToXmp.entries) {
      final stored = await info.stringEntry(PdfName(entry.key));
      if (stored == null) continue;
      final value = stored.decodeMappingText().trim();
      if (value.isEmpty) continue;
      final declared = xmpValues[entry.key];

      if (declared == null) {
        findings.add(PdfConformanceFinding(
          'xmp-info-missing-property',
          PdfConformanceSeverity.violation,
          'The document information dictionary sets /${entry.key} but the XMP '
              'packet carries no ${entry.value}. The two have to say the same '
              'thing, because a reader may consult either.',
          clause: 'ISO 19005-${level.part}:6.7.3',
        ));
        continue;
      }

      final agrees = entry.key.endsWith('Date')
          ? _sameInstant(value, declared)
          : value == declared.trim();
      if (!agrees) {
        findings.add(PdfConformanceFinding(
          'xmp-info-mismatch',
          PdfConformanceSeverity.violation,
          'The document information dictionary says /${entry.key} is "$value" '
              'while the XMP packet says ${entry.value} is "$declared".',
          clause: 'ISO 19005-${level.part}:6.7.3',
        ));
      }
    }
  }

  /// Compares a PDF date string (`D:20240102030405+00'00'`) with an XMP one
  /// (`2024-01-02T03:04:05+00:00`) by the instant they name.
  ///
  /// Only the digits carry the value in both forms, so the comparison is over
  /// the leading fourteen of them; a date that stops earlier is compared as
  /// far as both go, which is what a shorter date means.
  static bool _sameInstant(String pdfDate, String xmpDate) {
    final left = pdfDate.replaceAll(RegExp(r'[^0-9]'), '');
    final right = xmpDate.replaceAll(RegExp(r'[^0-9]'), '');
    if (left.isEmpty || right.isEmpty) return false;
    final length =
        [left.length, right.length, 14].reduce((a, b) => a < b ? a : b);
    return left.substring(0, length) == right.substring(0, length);
  }

  // --- tagging --------------------------------------------------------------

  static Future<void> _checkTagging(
    PdfDictionary catalog,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    if (!level.requiresTagging) return;

    final markInfo = await catalog.dictionaryEntry(PdfName.markInfo);
    final marked = await markInfo?.flagEntry(PdfName('Marked'));
    if (marked != true) {
      findings.add(PdfConformanceFinding(
        'not-marked',
        PdfConformanceSeverity.violation,
        '${level.label} requires /MarkInfo << /Marked true >> in the catalog.',
        clause: 'ISO 19005-${level.part}:6.8.2',
      ));
    }
    final root = await catalog.dictionaryEntry(PdfName.structTreeRoot);
    if (root == null) {
      findings.add(PdfConformanceFinding(
        'missing-structure-tree',
        PdfConformanceSeverity.violation,
        '${level.label} requires a /StructTreeRoot describing the logical '
            'structure.',
        clause: 'ISO 19005-${level.part}:6.8.2',
      ));
    } else {
      final scan = await scanStructureTree(root);
      if (!scan.hasElements) {
        findings.add(PdfConformanceFinding(
          'empty-structure-tree',
          PdfConformanceSeverity.violation,
          'The structure tree carries no elements, so it describes nothing.',
          clause: 'ISO 19005-${level.part}:6.8.2',
        ));
      }
      for (final issue in scan.issues) {
        findings.add(PdfConformanceFinding(
          issue.code,
          PdfConformanceSeverity.violation,
          issue.message,
          clause: 'ISO 19005-${level.part}:6.8.3',
        ));
      }
    }
    final lang = await catalog.stringEntry(PdfName('Lang'));
    if (lang == null) {
      findings.add(PdfConformanceFinding(
        'missing-lang',
        PdfConformanceSeverity.warning,
        'The catalog declares no /Lang; assistive technology cannot pick a '
            'pronunciation without it.',
        clause: 'ISO 19005-${level.part}:6.8.4',
      ));
    }
  }

  // --- pages ----------------------------------------------------------------

  /// Annotation subtypes no PDF/A profile permits.
  static const Set<String> _forbiddenAnnotations = {
    'FileAttachment',
    'Sound',
    'Movie',
    'Screen',
    'PrinterMark',
    'TrapNet',
    '3D',
    'RichMedia',
  };

  /// Action types no PDF/A profile permits.
  static const Set<String> _forbiddenActions = {
    'Launch',
    'Sound',
    'Movie',
    'ResetForm',
    'ImportData',
    'JavaScript',
    'SetState',
    'NoOp',
  };

  /// The named actions ISO 19005 keeps, all of them page navigation.
  static const Set<String> _permittedNamedActions = {
    'NextPage',
    'PrevPage',
    'FirstPage',
    'LastPage',
  };

  static Future<void> _checkPages(
    PdfDocument document,
    PdfAConformanceLevel level,
    String? intentColourSpace,
    FindingSink findings,
  ) async {
    final pageCount = document.pageHierarchy().pageTotal();
    for (var number = 1; number <= pageCount; number++) {
      final page = await document.pageAt(number);
      if (page == null) continue;
      final dictionary = page.pdfRepresentation();

      if (dictionary.containsKey(PdfName('AA'))) {
        findings.add(PdfConformanceFinding(
          'page-additional-actions',
          PdfConformanceSeverity.violation,
          'The page declares /AA additional actions.',
          clause: 'ISO 19005-${level.part}:6.6.2',
          page: number,
        ));
      }

      if (level.forbidsTransparency) {
        final group = await dictionary.dictionaryEntry(PdfName('Group'));
        final subtype = await group?.nameEntry(PdfName('S'));
        if (subtype?.getValue() == 'Transparency') {
          findings.add(PdfConformanceFinding(
            'page-transparency-group',
            PdfConformanceSeverity.violation,
            'The page carries a transparency group, which ${level.label} '
                '(built on PDF 1.4) does not permit.',
            clause: 'ISO 19005-1:6.4',
            page: number,
          ));
        }
      }

      await _checkAnnotations(page, number, level, findings);

      final resources = await dictionary.dictionaryEntry(PdfName.resources);
      final scan = await _scanPage(page, resources);
      if (scan != null) {
        _reportContent(scan, number, level, intentColourSpace, findings);
      }
      await _checkResources(
        resources,
        number,
        level,
        intentColourSpace,
        scan,
        findings,
        <PdfDictionary>{},
        0,
      );
    }
  }

  static Future<ContentStreamScan?> _scanPage(
    PdfPage page,
    PdfDictionary? resources,
  ) async {
    Uint8List content;
    try {
      content = await page.contentPayload();
    } on Object {
      return null;
    }
    if (content.isEmpty) return null;
    return scanContentStream(content, resources);
  }

  /// Turns the facts a content scan collected into findings.
  static void _reportContent(
    ContentStreamScan scan,
    int page,
    PdfAConformanceLevel level,
    String? intentColourSpace,
    FindingSink findings,
  ) {
    if (!scan.parsed) {
      findings.add(PdfConformanceFinding(
        'content-stream-unparsable',
        PdfConformanceSeverity.violation,
        'The content stream is not valid PDF content: ${scan.failure}.',
        clause: 'ISO 19005-${level.part}:6.2.1',
        page: page,
      ));
      return;
    }

    if (scan.unbalancedSaveRestore) {
      findings.add(PdfConformanceFinding(
        'unbalanced-graphics-state',
        PdfConformanceSeverity.violation,
        'The content stream does not pair its q and Q operators, so the '
            'graphics state it leaves behind depends on how a reader recovers '
            'from the imbalance.',
        clause: 'ISO 19005-${level.part}:6.2.1',
        page: page,
      ));
    }
    if (scan.unbalancedTextObjects) {
      findings.add(PdfConformanceFinding(
        'unbalanced-text-object',
        PdfConformanceSeverity.violation,
        'The content stream does not pair its BT and ET operators.',
        clause: 'ISO 19005-${level.part}:6.2.1',
        page: page,
      ));
    }
    for (final missing in scan.missingResources) {
      findings.add(PdfConformanceFinding(
        'undefined-resource',
        PdfConformanceSeverity.violation,
        'The content stream uses /$missing, which the resource dictionary '
            'does not define, so there is nothing to draw with.',
        clause: 'ISO 19005-${level.part}:6.2.1',
        page: page,
      ));
    }

    // Device colour only means something once an output intent says what the
    // numbers stand for. With no readable profile there is nothing to compare
    // against, and the missing intent has already been reported.
    if (intentColourSpace == null) return;
    if (scan.deviceColourSpaces.contains('DeviceRGB') &&
        intentColourSpace.trim() != 'RGB') {
      findings.add(PdfConformanceFinding(
        'device-rgb-without-rgb-output-intent',
        PdfConformanceSeverity.violation,
        'The page selects DeviceRGB but the output intent profile describes a '
            '"${intentColourSpace.trim()}" device, so the red, green and blue '
            'values name no particular colour.',
        clause: 'ISO 19005-${level.part}:6.2.3',
        page: page,
      ));
    }
    if (scan.deviceColourSpaces.contains('DeviceCMYK') &&
        intentColourSpace.trim() != 'CMYK') {
      findings.add(PdfConformanceFinding(
        'device-cmyk-without-cmyk-output-intent',
        PdfConformanceSeverity.violation,
        'The page selects DeviceCMYK but the output intent profile describes '
            'a "${intentColourSpace.trim()}" device.',
        clause: 'ISO 19005-${level.part}:6.2.4',
        page: page,
      ));
    }
  }

  static Future<void> _checkAnnotations(
    PdfPage page,
    int number,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final annotations =
        await page.pdfRepresentation().arrayEntry(PdfName.annots);
    if (annotations == null) return;

    for (var i = 0; i < annotations.size(); i++) {
      final annotation = await annotations.dictionaryEntry(i);
      if (annotation == null) continue;
      final subtype = (await annotation.nameEntry(PdfName.subtype))?.getValue();

      if (subtype != null && _forbiddenAnnotations.contains(subtype)) {
        findings.add(PdfConformanceFinding(
          'forbidden-annotation',
          PdfConformanceSeverity.violation,
          'The page carries a /$subtype annotation, which PDF/A does not '
              'permit.',
          clause: 'ISO 19005-${level.part}:6.6.1',
          page: number,
        ));
      }

      final flags = await annotation.integerEntry(PdfName('F')) ?? 0;
      const printFlag = 4, hiddenFlag = 2, noViewFlag = 32;
      if (flags & printFlag == 0) {
        findings.add(PdfConformanceFinding(
          'annotation-not-printable',
          PdfConformanceSeverity.violation,
          'An annotation does not set the Print flag, so it would be lost on '
              'paper.',
          clause: 'ISO 19005-${level.part}:6.6.1',
          page: number,
        ));
      }
      if (flags & hiddenFlag != 0 || flags & noViewFlag != 0) {
        findings.add(PdfConformanceFinding(
          'annotation-hidden',
          PdfConformanceSeverity.violation,
          'An annotation sets the Hidden or NoView flag.',
          clause: 'ISO 19005-${level.part}:6.6.1',
          page: number,
        ));
      }

      if (level.forbidsTransparency) {
        final opacity = await annotation.decimalEntry(PdfName('CA'));
        if (opacity != null && opacity != 1.0) {
          findings.add(PdfConformanceFinding(
            'annotation-transparent',
            PdfConformanceSeverity.violation,
            'An annotation declares /CA $opacity; ${level.label} requires 1.0.',
            clause: 'ISO 19005-1:6.5.3',
            page: number,
          ));
        }
      }

      if (subtype != 'Popup' && subtype != 'Link') {
        final appearance = await annotation.dictionaryEntry(PdfName('AP'));
        if (appearance == null || !appearance.containsKey(PdfName('N'))) {
          findings.add(PdfConformanceFinding(
            'annotation-without-appearance',
            PdfConformanceSeverity.violation,
            'A /$subtype annotation has no normal appearance stream, so its '
                'rendering would depend on the reader.',
            clause: 'ISO 19005-${level.part}:6.6.1',
            page: number,
          ));
        }
      }

      if (annotation.containsKey(PdfName('AA'))) {
        findings.add(PdfConformanceFinding(
          'annotation-additional-actions',
          PdfConformanceSeverity.violation,
          'A /$subtype annotation declares /AA additional actions, which run '
              'on events a reader generates.',
          clause: 'ISO 19005-${level.part}:6.6.2',
          page: number,
        ));
      }

      final action = await annotation.dictionaryEntry(PdfName('A'));
      if (action != null) {
        await _checkAction(action, level, findings, page: number);
      }
    }
  }

  static Future<void> _checkAction(
    PdfDictionary action,
    PdfAConformanceLevel level,
    FindingSink findings, {
    int? page,
  }) async {
    final type = (await action.nameEntry(PdfName('S')))?.getValue();
    if (type != null && _forbiddenActions.contains(type)) {
      findings.add(PdfConformanceFinding(
        'forbidden-action',
        PdfConformanceSeverity.violation,
        'A /$type action is present; PDF/A permits only navigation actions.',
        clause: 'ISO 19005-${level.part}:6.6.1',
        page: page,
      ));
    }
    if (type == 'Named') {
      final name = (await action.nameEntry(PdfName.n))?.getValue();
      if (name == null || !_permittedNamedActions.contains(name)) {
        findings.add(PdfConformanceFinding(
          'forbidden-named-action',
          PdfConformanceSeverity.violation,
          'A named action asks for /${name ?? "(unnamed)"}; PDF/A keeps only '
              'the four page navigation names, because every other name asks '
              'the reader application to do something of its own.',
          clause: 'ISO 19005-${level.part}:6.6.1',
          page: page,
        ));
      }
    }
  }

  // --- resources ------------------------------------------------------------

  static Future<void> _checkResources(
    PdfDictionary? resources,
    int number,
    PdfAConformanceLevel level,
    String? intentColourSpace,
    ContentStreamScan? scan,
    FindingSink findings,
    Set<PdfDictionary> visited,
    int depth,
  ) async {
    if (resources == null || depth > 8 || !visited.add(resources)) return;

    final fonts = await resources.dictionaryEntry(PdfName.font);
    if (fonts != null) {
      for (final key in fonts.keySet()) {
        final font = await fonts.dictionaryEntry(key);
        if (font != null) {
          await _checkFont(
            font,
            number,
            level,
            findings,
            scan?.shownTextByFont[key.getValue()] ?? const [],
          );
        }
      }
    }

    final states = await resources.dictionaryEntry(PdfName.extGState);
    if (states != null) {
      for (final key in states.keySet()) {
        final state = await states.dictionaryEntry(key);
        if (state != null) {
          await _checkExtGState(state, number, level, findings);
        }
      }
    }

    final xobjects = await resources.dictionaryEntry(PdfName.xObject);
    if (xobjects != null) {
      for (final key in xobjects.keySet()) {
        final xobject = await xobjects.streamEntry(key);
        if (xobject == null) continue;
        await _checkXObject(
            xobject, number, level, intentColourSpace, findings);

        final subtype = (await xobject.nameEntry(PdfName.subtype))?.getValue();
        if (subtype != 'Form') continue;
        // A form XObject is a content stream with a resource dictionary of its
        // own; everything the page rules say applies inside it too.
        final inner =
            await xobject.dictionaryEntry(PdfName.resources) ?? resources;
        ContentStreamScan? innerScan;
        try {
          final content = await xobject.getBytes();
          if (content != null && content.isNotEmpty) {
            innerScan = await scanContentStream(content, inner);
          }
        } on Object {
          innerScan = null;
        }
        if (innerScan != null) {
          _reportContent(innerScan, number, level, intentColourSpace, findings);
        }
        await _checkResources(inner, number, level, intentColourSpace,
            innerScan, findings, visited, depth + 1);
      }
    }
  }

  // --- fonts ----------------------------------------------------------------

  /// Font subtypes that carry their own glyph programs elsewhere and are
  /// checked through their descendants instead.
  static const Set<String> _compositeFonts = {'Type0'};

  /// Bit 3 of a font descriptor's /Flags: the font has its own built-in
  /// encoding rather than following a standard one.
  static const int _symbolicFlag = 4;

  static Future<void> _checkFont(
    PdfDictionary font,
    int page,
    PdfAConformanceLevel level,
    FindingSink findings,
    List<Uint8List> shownText,
  ) async {
    final subtype = (await font.nameEntry(PdfName.subtype))?.getValue();
    final baseFont =
        (await font.nameEntry(PdfName.baseFont))?.getValue() ?? 'unnamed';

    if (subtype == 'Type3') {
      // A Type 3 font carries its glyphs as content streams, so there is
      // nothing to embed; its charprocs are covered by the content stream
      // rules applied to the resources they name.
      return;
    }

    if (_compositeFonts.contains(subtype)) {
      final descendants = await font.arrayEntry(PdfName('DescendantFonts'));
      final descendant = await descendants?.dictionaryEntry(0);
      if (descendant == null) {
        findings.add(PdfConformanceFinding(
          'composite-font-without-descendant',
          PdfConformanceSeverity.violation,
          'The Type0 font $baseFont has no descendant font.',
          clause: 'ISO 19005-${level.part}:6.3.4',
          page: page,
        ));
        return;
      }
      final embedded = await _checkFontDescriptor(
          descendant, baseFont, page, level, findings);
      await _checkCidFont(
          descendant, baseFont, page, level, embedded, findings);

      final encoding = (await font.nameEntry(PdfName.encoding))?.getValue();
      final identity = encoding == null || encoding.startsWith('Identity');
      if (level.requiresUnicodeMapping &&
          !font.containsKey(PdfName.toUnicode) &&
          identity) {
        findings.add(PdfConformanceFinding(
          'font-without-tounicode',
          PdfConformanceSeverity.violation,
          'The font $baseFont has no /ToUnicode map, so ${level.label} '
              'cannot guarantee its text can be extracted.',
          clause: 'ISO 19005-${level.part}:6.3.8',
          page: page,
        ));
      } else if (level.requiresUnicodeMapping && identity) {
        await _checkUnicodeCoverage(
            font, baseFont, page, level, shownText, 2, findings);
      }
      return;
    }

    await _checkFontDescriptor(font, baseFont, page, level, findings);
    await _checkSimpleFontMetrics(font, baseFont, page, level, findings);
    await _checkSimpleFontEncoding(
        font, subtype, baseFont, page, level, findings);

    if (level.requiresUnicodeMapping) {
      await _checkSimpleFontUnicode(
          font, baseFont, page, level, shownText, findings);
    }
  }

  /// Returns true when the descriptor embeds a font program.
  static Future<bool> _checkFontDescriptor(
    PdfDictionary font,
    String baseFont,
    int page,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final descriptor = await font.dictionaryEntry(PdfName.fontDescriptor);
    if (descriptor == null) {
      findings.add(PdfConformanceFinding(
        'font-without-descriptor',
        PdfConformanceSeverity.violation,
        'The font $baseFont has no /FontDescriptor, so it cannot embed a '
            'font program. PDF/A requires every font to be embedded, including '
            'the standard 14.',
        clause: 'ISO 19005-${level.part}:6.3.4',
        page: page,
      ));
      return false;
    }
    final embedded = descriptor.containsKey(PdfName.fontFile) ||
        descriptor.containsKey(PdfName.fontFile2) ||
        descriptor.containsKey(PdfName.fontFile3);
    if (!embedded) {
      findings.add(PdfConformanceFinding(
        'font-not-embedded',
        PdfConformanceSeverity.violation,
        'The font $baseFont is not embedded; a reader without it would '
            'substitute another face and change the page.',
        clause: 'ISO 19005-${level.part}:6.3.4',
        page: page,
      ));
    }
    return embedded;
  }

  /// Rules a CIDFont carries on top of the common font rules.
  static Future<void> _checkCidFont(
    PdfDictionary descendant,
    String baseFont,
    int page,
    PdfAConformanceLevel level,
    bool embedded,
    FindingSink findings,
  ) async {
    final subtype = (await descendant.nameEntry(PdfName.subtype))?.getValue();
    final descriptor = await descendant.dictionaryEntry(PdfName.fontDescriptor);

    // PDF/A-1 to -3 require the descriptor of an embedded CIDFont to list the
    // CIDs the program actually contains, so a reader can tell a subset from
    // a damaged font. PDF/A-4 dropped the requirement.
    if (embedded &&
        level.part != '4' &&
        descriptor != null &&
        !descriptor.containsKey(PdfName('CIDSet'))) {
      findings.add(PdfConformanceFinding(
        'cidfont-without-cidset',
        PdfConformanceSeverity.violation,
        'The CIDFont $baseFont embeds a font program but its descriptor has '
            'no /CIDSet saying which CIDs that program defines.',
        clause: 'ISO 19005-${level.part}:6.3.3',
        page: page,
      ));
    }

    if (subtype != 'CIDFontType2') return;
    final map = await descendant.get(PdfName('CIDToGIDMap'));
    if (map == null) {
      if (level.part == '1') {
        findings.add(PdfConformanceFinding(
          'cidfont-without-cidtogidmap',
          PdfConformanceSeverity.violation,
          'The CIDFontType2 $baseFont declares no /CIDToGIDMap; '
              '${level.label} requires the entry to be present and to be '
              'either /Identity or a stream.',
          clause: 'ISO 19005-1:6.3.3',
          page: page,
        ));
      }
      return;
    }
    if (map.objectKind() == PdfObjectType.name &&
        (map as PdfName).getValue() != 'Identity') {
      findings.add(PdfConformanceFinding(
        'cidfont-bad-cidtogidmap',
        PdfConformanceSeverity.violation,
        'The CIDFontType2 $baseFont declares /CIDToGIDMap /${map.getValue()}; '
            'only /Identity or a stream maps CIDs to glyphs unambiguously.',
        clause: 'ISO 19005-${level.part}:6.3.3',
        page: page,
      ));
    }
  }

  /// A simple font's metrics have to come from the file, and have to describe
  /// exactly the codes the font claims.
  static Future<void> _checkSimpleFontMetrics(
    PdfDictionary font,
    String baseFont,
    int page,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final widths = await font.arrayEntry(PdfName.widths);
    if (widths == null) {
      findings.add(PdfConformanceFinding(
        'font-without-widths',
        PdfConformanceSeverity.violation,
        'The font $baseFont has no /Widths array, so its metrics would come '
            'from the reader.',
        clause: 'ISO 19005-${level.part}:6.3.5',
        page: page,
      ));
      return;
    }

    final first = await font.integerEntry(PdfName('FirstChar'));
    final last = await font.integerEntry(PdfName('LastChar'));
    if (first == null || last == null) {
      findings.add(PdfConformanceFinding(
        'font-without-char-range',
        PdfConformanceSeverity.violation,
        'The font $baseFont has a /Widths array but no /FirstChar and '
            '/LastChar, so nothing says which codes those widths belong to.',
        clause: 'ISO 19005-${level.part}:6.3.5',
        page: page,
      ));
      return;
    }
    final expected = last - first + 1;
    if (widths.size() != expected) {
      findings.add(PdfConformanceFinding(
        'font-widths-inconsistent',
        PdfConformanceSeverity.violation,
        'The font $baseFont covers codes $first to $last, which is $expected '
            'widths, but its /Widths array has ${widths.size()} entries. The '
            'codes past the end would be measured by the reader.',
        clause: 'ISO 19005-${level.part}:6.3.5',
        page: page,
      ));
    }
  }

  /// A symbolic TrueType font carries its own character map, and an /Encoding
  /// on top of it would say something the font contradicts.
  static Future<void> _checkSimpleFontEncoding(
    PdfDictionary font,
    String? subtype,
    String baseFont,
    int page,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    if (subtype != 'TrueType') return;
    final descriptor = await font.dictionaryEntry(PdfName.fontDescriptor);
    final flags = await descriptor?.integerEntry(PdfName('Flags')) ?? 0;
    if (flags & _symbolicFlag == 0) return;
    if (!font.containsKey(PdfName.encoding)) return;

    findings.add(PdfConformanceFinding(
      'symbolic-truetype-with-encoding',
      PdfConformanceSeverity.violation,
      'The symbolic TrueType font $baseFont carries an /Encoding entry. A '
          'symbolic font maps codes through its own cmap, so an /Encoding can '
          'only disagree with it.',
      clause: 'ISO 19005-${level.part}:6.3.7',
      page: page,
    ));
  }

  /// The `u` and `a` levels promise the text can be read back out, which needs
  /// a Unicode value for every code drawn.
  static Future<void> _checkSimpleFontUnicode(
    PdfDictionary font,
    String baseFont,
    int page,
    PdfAConformanceLevel level,
    List<Uint8List> shownText,
    FindingSink findings,
  ) async {
    if (font.containsKey(PdfName.toUnicode)) {
      await _checkUnicodeCoverage(
          font, baseFont, page, level, shownText, 1, findings);
      return;
    }

    // A named standard encoding already maps every code to a character, so a
    // font that uses one needs no /ToUnicode. Anything else does.
    final encoding = await font.get(PdfName.encoding);
    final named =
        encoding != null && encoding.objectKind() == PdfObjectType.name
            ? (encoding as PdfName).getValue()
            : null;
    const standard = {
      'WinAnsiEncoding',
      'MacRomanEncoding',
      'MacExpertEncoding',
      'StandardEncoding',
    };
    if (named != null && standard.contains(named)) return;

    findings.add(PdfConformanceFinding(
      'font-without-tounicode',
      PdfConformanceSeverity.violation,
      'The font $baseFont has no /ToUnicode map and does not use a named '
          'standard encoding, so ${level.label} cannot guarantee its text can '
          'be extracted.',
      clause: 'ISO 19005-${level.part}:6.3.8',
      page: page,
    ));
  }

  /// Checks that the `/ToUnicode` map covers the codes the page actually drew.
  ///
  /// A map that exists but omits the codes in use is the common way a file
  /// claims level `u` without delivering it, and it is decidable here because
  /// the content scan recorded the strings that were shown.
  static Future<void> _checkUnicodeCoverage(
    PdfDictionary font,
    String baseFont,
    int page,
    PdfAConformanceLevel level,
    List<Uint8List> shownText,
    int codeBytes,
    FindingSink findings,
  ) async {
    if (shownText.isEmpty) return;
    final stream = await font.streamEntry(PdfName.toUnicode);
    if (stream == null) return;

    Map<int, String> mappings;
    try {
      mappings = (await UnicodeCodeMap.fromStream(stream)).mappings;
    } on Object {
      findings.add(PdfConformanceFinding(
        'tounicode-unreadable',
        PdfConformanceSeverity.violation,
        'The /ToUnicode map of $baseFont is not a CMap that can be read, so '
            'the text it maps cannot be extracted.',
        clause: 'ISO 19005-${level.part}:6.3.8',
        page: page,
      ));
      return;
    }

    final uncovered = <int>{};
    for (final string in shownText) {
      for (var i = 0; i + codeBytes <= string.length; i += codeBytes) {
        var code = 0;
        for (var b = 0; b < codeBytes; b++) {
          code = (code << 8) | string[i + b];
        }
        final text = mappings[code];
        // A code mapped to U+0000 is mapped to nothing: ISO 19005 singles it
        // out because it is what a tool writes when it does not know.
        if (text == null || text.isEmpty || text.codeUnitAt(0) == 0) {
          uncovered.add(code);
        }
      }
    }
    if (uncovered.isEmpty) return;

    final sample = (uncovered.toList()..sort()).take(8).map(
        (code) => '0x${code.toRadixString(16).padLeft(codeBytes * 2, '0')}');
    findings.add(PdfConformanceFinding(
      'tounicode-incomplete',
      PdfConformanceSeverity.violation,
      'The page draws ${uncovered.length} code(s) with $baseFont that its '
          '/ToUnicode map does not give a Unicode value for '
          '(${sample.join(', ')}). ${level.label} promises the text can be '
          'extracted, and these characters cannot be.',
      clause: 'ISO 19005-${level.part}:6.3.8',
      page: page,
    ));
  }

  // --- graphics state and XObjects ------------------------------------------

  static Future<void> _checkExtGState(
    PdfDictionary state,
    int page,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    for (final key in const ['TR', 'TR2']) {
      if (state.containsKey(PdfName(key))) {
        final value = await state.nameEntry(PdfName(key));
        if (value?.getValue() != 'Default') {
          findings.add(PdfConformanceFinding(
            'transfer-function',
            PdfConformanceSeverity.violation,
            'A graphics state sets /$key, a transfer function that rewrites '
                'colour after rendering.',
            clause: 'ISO 19005-${level.part}:6.2.4',
            page: page,
          ));
        }
      }
    }

    if (!level.forbidsTransparency) return;

    final softMask = await state.get(PdfName('SMask'));
    if (softMask != null &&
        !(softMask.objectKind() == PdfObjectType.name &&
            (softMask as PdfName).getValue() == 'None')) {
      findings.add(PdfConformanceFinding(
        'soft-mask',
        PdfConformanceSeverity.violation,
        'A graphics state sets a soft mask; ${level.label} permits only '
            '/SMask /None.',
        clause: 'ISO 19005-1:6.4',
        page: page,
      ));
    }
    for (final key in const ['CA', 'ca']) {
      final alpha = await state.decimalEntry(PdfName(key));
      if (alpha != null && alpha != 1.0) {
        findings.add(PdfConformanceFinding(
          'constant-alpha',
          PdfConformanceSeverity.violation,
          'A graphics state sets /$key $alpha; ${level.label} requires 1.0.',
          clause: 'ISO 19005-1:6.4',
          page: page,
        ));
      }
    }
    final blend = await state.nameEntry(PdfName('BM'));
    final blendValue = blend?.getValue();
    if (blendValue != null &&
        blendValue != 'Normal' &&
        blendValue != 'Compatible') {
      findings.add(PdfConformanceFinding(
        'blend-mode',
        PdfConformanceSeverity.violation,
        'A graphics state sets /BM /$blendValue; ${level.label} permits only '
            'Normal and Compatible.',
        clause: 'ISO 19005-1:6.4',
        page: page,
      ));
    }
  }

  static Future<void> _checkXObject(
    PdfStream xobject,
    int page,
    PdfAConformanceLevel level,
    String? intentColourSpace,
    FindingSink findings,
  ) async {
    final subtype = (await xobject.nameEntry(PdfName.subtype))?.getValue();

    if (subtype == 'Image') {
      final interpolate = await xobject.flagEntry(PdfName('Interpolate'));
      if (interpolate == true) {
        findings.add(PdfConformanceFinding(
          'image-interpolate',
          PdfConformanceSeverity.violation,
          'An image sets /Interpolate true, which makes its rendering depend '
              'on the reader.',
          clause: 'ISO 19005-${level.part}:6.2.8',
          page: page,
        ));
      }
      if (level.forbidsTransparency && xobject.containsKey(PdfName('SMask'))) {
        final mask = await xobject.nameEntry(PdfName('SMask'));
        if (mask?.getValue() != 'None') {
          findings.add(PdfConformanceFinding(
            'image-soft-mask',
            PdfConformanceSeverity.violation,
            'An image carries a soft mask, which ${level.label} does not '
                'permit.',
            clause: 'ISO 19005-1:6.4',
            page: page,
          ));
        }
      }
      await _checkImageColourSpace(
          xobject, page, level, intentColourSpace, findings);
    }

    if (subtype == 'Form' && level.forbidsTransparency) {
      final group = await xobject.dictionaryEntry(PdfName('Group'));
      final groupType = await group?.nameEntry(PdfName('S'));
      if (groupType?.getValue() == 'Transparency') {
        findings.add(PdfConformanceFinding(
          'form-transparency-group',
          PdfConformanceSeverity.violation,
          'A form XObject carries a transparency group, which ${level.label} '
              'does not permit.',
          clause: 'ISO 19005-1:6.4',
          page: page,
        ));
      }
    }

    if (xobject.containsKey(PdfName('PS')) || (subtype == 'PS')) {
      findings.add(PdfConformanceFinding(
        'postscript-xobject',
        PdfConformanceSeverity.violation,
        'A PostScript XObject is present; PDF/A does not permit embedded '
            'PostScript.',
        clause: 'ISO 19005-${level.part}:6.2.9',
        page: page,
      ));
    }
  }

  /// An image's samples are in a colour space just as a fill is, and the same
  /// output intent rule applies to them.
  static Future<void> _checkImageColourSpace(
    PdfStream image,
    int page,
    PdfAConformanceLevel level,
    String? intentColourSpace,
    FindingSink findings,
  ) async {
    if (intentColourSpace == null) return;
    final space = await image.nameEntry(PdfName.colorSpace);
    final value = space?.getValue();
    if (value == 'DeviceRGB' && intentColourSpace.trim() != 'RGB') {
      findings.add(PdfConformanceFinding(
        'device-rgb-without-rgb-output-intent',
        PdfConformanceSeverity.violation,
        'An image declares /ColorSpace /DeviceRGB but the output intent '
            'profile describes a "${intentColourSpace.trim()}" device.',
        clause: 'ISO 19005-${level.part}:6.2.3',
        page: page,
      ));
    }
    if (value == 'DeviceCMYK' && intentColourSpace.trim() != 'CMYK') {
      findings.add(PdfConformanceFinding(
        'device-cmyk-without-cmyk-output-intent',
        PdfConformanceSeverity.violation,
        'An image declares /ColorSpace /DeviceCMYK but the output intent '
            'profile describes a "${intentColourSpace.trim()}" device.',
        clause: 'ISO 19005-${level.part}:6.2.4',
        page: page,
      ));
    }
  }

  // --- object graph ---------------------------------------------------------

  /// Filters a profile forbids, each mapped to the finding code it raises and
  /// the reason the profile keeps it out.
  static Map<String, (String, String)> _forbiddenFilters(
          PdfAConformanceLevel level) =>
      {
        if (level.forbidsLzw)
          'LZWDecode': (
            'lzw-filter',
            'its patent history kept it out of the archival profiles'
          ),
        // JPEG 2000 arrived with PDF 1.5, after the PDF 1.4 base of PDF/A-1.
        if (level.part == '1')
          'JPXDecode': (
            'jpxdecode-filter',
            'JPEG 2000 is a PDF 1.5 feature and ${level.label} is built on '
                'PDF 1.4'
          ),
        'Crypt': (
          'crypt-filter',
          'a crypt filter means the stream is encrypted, and an archival file '
              'must be readable without a key'
        ),
      };

  static Future<void> _checkObjects(
    PdfDocument document,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final forbidden = _forbiddenFilters(level);
    final xref = document.crossReferenceTable();
    var reported = 0;
    for (var number = 1; number < xref.size() && reported < 40; number++) {
      final reference = xref.get(number);
      if (reference == null || reference.isFree()) continue;
      PdfObject? object;
      try {
        object = await reference.targetObject(true);
      } on Object {
        continue;
      }
      if (object == null || object.objectKind() != PdfObjectType.stream) {
        continue;
      }
      final stream = object as PdfStream;
      final filters = await _filtersOf(stream);
      for (final entry in forbidden.entries) {
        if (!filters.contains(entry.key)) continue;
        findings.add(PdfConformanceFinding(
          entry.value.$1,
          PdfConformanceSeverity.violation,
          'A stream uses the ${entry.key} filter, which ${level.label} does '
          'not permit: ${entry.value.$2}.',
          clause: 'ISO 19005-${level.part}:6.1.10',
          objectNumber: number,
        ));
        reported++;
      }
      if (stream.containsKey(PdfName('F'))) {
        findings.add(PdfConformanceFinding(
          'external-stream',
          PdfConformanceSeverity.violation,
          'A stream keeps its data in an external file (/F), so the document '
              'is not self contained.',
          clause: 'ISO 19005-${level.part}:6.1.7',
          objectNumber: number,
        ));
        reported++;
      }
    }
  }

  static Future<Set<String>> _filtersOf(PdfStream stream) async {
    final filter = await stream.get(PdfName.filter);
    if (filter == null) return const {};
    if (filter.objectKind() == PdfObjectType.name) {
      return {(filter as PdfName).getValue()};
    }
    if (filter.objectKind() == PdfObjectType.array) {
      final array = filter as PdfArray;
      final names = <String>{};
      for (var i = 0; i < array.size(); i++) {
        final name = await array.nameEntry(i);
        if (name != null) names.add(name.getValue());
      }
      return names;
    }
    return const {};
  }
}
