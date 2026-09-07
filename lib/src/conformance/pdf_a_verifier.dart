import 'dart:convert';
import 'dart:typed_data';

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
import 'finding_sink.dart';
import 'pdf_conformance.dart';
import 'pdf_conformance_report.dart';
import 'xmp_identification.dart';

/// Checks an existing document against a PDF/A profile.
///
/// The verifier reads; it never rewrites the input. It decides the rules that
/// can be settled from the document's object graph — metadata, output intents,
/// font embedding, encryption, forbidden actions and annotations, transparency
/// and filters. Rules that need a content-stream interpreter or an ICC parser
/// are listed in [PdfConformanceReport.unverifiedRules] rather than silently
/// passed.
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
    final properties = CraftReaderProperties();
    if (password != null) {
      properties.setPassword(Uint8List.fromList(utf8.encode(password)));
    }

    final reader = CraftPdfReader.fromBytes(bytes, properties);
    final document = await CraftPdfDocument.open(reader);
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
      await _checkOutputIntents(catalog, target, findings);
      await _checkCatalogEntries(catalog, target, findings);
      await _checkTagging(catalog, target, findings);
      await _checkPages(document, target, findings);
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

  static List<String> _unverified(PdfAConformanceLevel level) => [
        'Content stream operators (colour operators used without a matching '
            'output intent, text rendering mode 7, unbalanced q/Q).',
        'ICC profile validity inside /DestOutputProfile.',
        'Glyph presence: whether every code used on a page exists in the '
            'embedded font program.',
        if (level.requiresUnicodeMapping)
          'Completeness of /ToUnicode coverage for every glyph actually drawn.',
        if (level.requiresTagging)
          'Semantic correctness of the structure tree (heading nesting, '
              'table regularity, reading order).',
      ];

  // --- document wide --------------------------------------------------------

  static Future<void> _checkVersion(
    CraftPdfDocument document,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final version = (document.formatVersion() ?? CraftPdfVersion.PDF_1_7)
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
    CraftPdfDocument document,
    FindingSink findings,
  ) async {
    if (document.fileTrailer().containsKey(CraftPdfName.encrypt)) {
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
    CraftPdfDictionary catalog,
    FindingSink findings,
  ) async {
    if (!catalog.containsKey(CraftPdfName.metadata)) {
      findings.add(const PdfConformanceFinding(
        'missing-metadata',
        PdfConformanceSeverity.violation,
        'The catalog has no /Metadata entry; PDF/A identification lives in an '
            'XMP packet there.',
        clause: 'ISO 19005-1:6.7.2',
      ));
      return;
    }
    final stream = await catalog.streamEntry(CraftPdfName.metadata);
    if (stream == null) {
      findings.add(const PdfConformanceFinding(
        'metadata-not-a-stream',
        PdfConformanceSeverity.violation,
        'The catalog /Metadata entry does not resolve to a stream.',
        clause: 'ISO 19005-1:6.7.2',
      ));
      return;
    }
    if (stream.containsKey(CraftPdfName.filter)) {
      findings.add(const PdfConformanceFinding(
        'metadata-filtered',
        PdfConformanceSeverity.violation,
        'The XMP metadata stream is filtered. It must be stored uncompressed '
            'so a reader can find the packet without decoding the file.',
        clause: 'ISO 19005-1:6.7.2',
      ));
    }
  }

  static Future<void> _checkOutputIntents(
    CraftPdfDictionary catalog,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final intents = await catalog.arrayEntry(CraftPdfName('OutputIntents'));
    if (intents == null || intents.size() == 0) {
      findings.add(PdfConformanceFinding(
        'missing-output-intent',
        PdfConformanceSeverity.violation,
        'The catalog declares no /OutputIntents. A PDF/A file that uses '
            'device colour needs one to define what those values mean.',
        clause: 'ISO 19005-${level.part}:6.2.2',
      ));
      return;
    }

    var seenPdfA = false;
    CraftPdfObject? firstProfile;
    for (var i = 0; i < intents.size(); i++) {
      final intent = await intents.dictionaryEntry(i);
      if (intent == null) continue;
      final subtype = await intent.nameEntry(CraftPdfName('S'));
      if (subtype?.getValue() == 'GTS_PDFA1') {
        seenPdfA = true;
        final profile = await intent.get(CraftPdfName('DestOutputProfile'));
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
        }
        if (!intent.containsKey(CraftPdfName('OutputConditionIdentifier'))) {
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
  }

  /// Entries a PDF/A catalog must not carry, with the clause that forbids them.
  static const Map<String, String> _forbiddenCatalogEntries = {
    'AA': 'a catalog must not declare additional actions',
    'OCProperties': 'optional content is not permitted',
  };

  static Future<void> _checkCatalogEntries(
    CraftPdfDictionary catalog,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    for (final entry in _forbiddenCatalogEntries.entries) {
      // Optional content arrived with PDF 1.5 and is allowed from PDF/A-2 on.
      if (entry.key == 'OCProperties' && level.part != '1') continue;
      if (catalog.containsKey(CraftPdfName(entry.key))) {
        findings.add(PdfConformanceFinding(
          'catalog-${entry.key.toLowerCase()}',
          PdfConformanceSeverity.violation,
          'The catalog contains /${entry.key}: ${entry.value}.',
          clause: 'ISO 19005-${level.part}:6.6.2',
        ));
      }
    }

    final names = await catalog.dictionaryEntry(CraftPdfName('Names'));
    if (names != null) {
      if (names.containsKey(CraftPdfName('JavaScript'))) {
        findings.add(PdfConformanceFinding(
          'catalog-javascript',
          PdfConformanceSeverity.violation,
          'The name dictionary contains /JavaScript. A PDF/A file must not '
              'carry executable content.',
          clause: 'ISO 19005-${level.part}:6.6.1',
        ));
      }
      if (!level.allowsEmbeddedFiles &&
          names.containsKey(CraftPdfName('EmbeddedFiles'))) {
        findings.add(PdfConformanceFinding(
          'catalog-embedded-files',
          PdfConformanceSeverity.violation,
          'The name dictionary contains /EmbeddedFiles, which ${level.label} '
              'does not permit.',
          clause: 'ISO 19005-${level.part}:6.1.11',
        ));
      }
    }

    final openAction = await catalog.get(CraftPdfName('OpenAction'));
    if (openAction != null &&
        openAction.objectKind() == PdfObjectType.dictionary) {
      await _checkAction(openAction as CraftPdfDictionary, level, findings);
    }
  }

  static Future<void> _checkTagging(
    CraftPdfDictionary catalog,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    if (!level.requiresTagging) return;

    final markInfo = await catalog.dictionaryEntry(CraftPdfName.markInfo);
    final marked = await markInfo?.flagEntry(CraftPdfName('Marked'));
    if (marked != true) {
      findings.add(PdfConformanceFinding(
        'not-marked',
        PdfConformanceSeverity.violation,
        '${level.label} requires /MarkInfo << /Marked true >> in the catalog.',
        clause: 'ISO 19005-${level.part}:6.8.2',
      ));
    }
    if (!catalog.containsKey(CraftPdfName.structTreeRoot)) {
      findings.add(PdfConformanceFinding(
        'missing-structure-tree',
        PdfConformanceSeverity.violation,
        '${level.label} requires a /StructTreeRoot describing the logical '
            'structure.',
        clause: 'ISO 19005-${level.part}:6.8.2',
      ));
    }
    final lang = await catalog.stringEntry(CraftPdfName('Lang'));
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

  static Future<void> _checkPages(
    CraftPdfDocument document,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final pageCount = document.pageHierarchy().pageTotal();
    for (var number = 1; number <= pageCount; number++) {
      final page = await document.pageAt(number);
      if (page == null) continue;
      final dictionary = page.pdfRepresentation();

      if (dictionary.containsKey(CraftPdfName('AA'))) {
        findings.add(PdfConformanceFinding(
          'page-additional-actions',
          PdfConformanceSeverity.violation,
          'The page declares /AA additional actions.',
          clause: 'ISO 19005-${level.part}:6.6.2',
          page: number,
        ));
      }

      if (level.forbidsTransparency) {
        final group = await dictionary.dictionaryEntry(CraftPdfName('Group'));
        final subtype = await group?.nameEntry(CraftPdfName('S'));
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
      await _checkPageResources(page, number, level, findings);
    }
  }

  static Future<void> _checkAnnotations(
    CraftPdfPage page,
    int number,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final annotations =
        await page.pdfRepresentation().arrayEntry(CraftPdfName.annots);
    if (annotations == null) return;

    for (var i = 0; i < annotations.size(); i++) {
      final annotation = await annotations.dictionaryEntry(i);
      if (annotation == null) continue;
      final subtype =
          (await annotation.nameEntry(CraftPdfName.subtype))?.getValue();

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

      final flags = await annotation.integerEntry(CraftPdfName('F')) ?? 0;
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
        final opacity = await annotation.decimalEntry(CraftPdfName('CA'));
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
        final appearance = await annotation.dictionaryEntry(CraftPdfName('AP'));
        if (appearance == null || !appearance.containsKey(CraftPdfName('N'))) {
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

      final action = await annotation.dictionaryEntry(CraftPdfName('A'));
      if (action != null) {
        await _checkAction(action, level, findings, page: number);
      }
    }
  }

  static Future<void> _checkAction(
    CraftPdfDictionary action,
    PdfAConformanceLevel level,
    FindingSink findings, {
    int? page,
  }) async {
    final type = (await action.nameEntry(CraftPdfName('S')))?.getValue();
    if (type != null && _forbiddenActions.contains(type)) {
      findings.add(PdfConformanceFinding(
        'forbidden-action',
        PdfConformanceSeverity.violation,
        'A /$type action is present; PDF/A permits only navigation actions.',
        clause: 'ISO 19005-${level.part}:6.6.1',
        page: page,
      ));
    }
  }

  static Future<void> _checkPageResources(
    CraftPdfPage page,
    int number,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final resources =
        await page.pdfRepresentation().dictionaryEntry(CraftPdfName.resources);
    if (resources == null) return;

    final fonts = await resources.dictionaryEntry(CraftPdfName.font);
    if (fonts != null) {
      for (final key in fonts.keySet()) {
        final font = await fonts.dictionaryEntry(key);
        if (font != null) {
          await _checkFont(font, number, level, findings);
        }
      }
    }

    final states = await resources.dictionaryEntry(CraftPdfName.extGState);
    if (states != null) {
      for (final key in states.keySet()) {
        final state = await states.dictionaryEntry(key);
        if (state != null) {
          await _checkExtGState(state, number, level, findings);
        }
      }
    }

    final xobjects = await resources.dictionaryEntry(CraftPdfName.xObject);
    if (xobjects != null) {
      for (final key in xobjects.keySet()) {
        final xobject = await xobjects.streamEntry(key);
        if (xobject != null) {
          await _checkXObject(xobject, number, level, findings);
        }
      }
    }
  }

  /// Font subtypes that carry their own glyph programs elsewhere and are
  /// checked through their descendants instead.
  static const Set<String> _compositeFonts = {'Type0'};

  static Future<void> _checkFont(
    CraftPdfDictionary font,
    int page,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final subtype = (await font.nameEntry(CraftPdfName.subtype))?.getValue();
    final baseFont =
        (await font.nameEntry(CraftPdfName.baseFont))?.getValue() ?? 'unnamed';

    if (subtype == 'Type3') {
      // A Type 3 font carries its glyphs as content streams, so there is
      // nothing to embed; its charprocs are covered by the content stream
      // rules this verifier does not evaluate.
      return;
    }

    if (_compositeFonts.contains(subtype)) {
      final descendants =
          await font.arrayEntry(CraftPdfName('DescendantFonts'));
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
      await _checkFontDescriptor(descendant, baseFont, page, level, findings);
      if (level.requiresUnicodeMapping &&
          !font.containsKey(CraftPdfName('ToUnicode'))) {
        final encoding =
            (await font.nameEntry(CraftPdfName.encoding))?.getValue();
        // The two identity encodings carry no implicit Unicode mapping.
        if (encoding == null || encoding.startsWith('Identity')) {
          findings.add(PdfConformanceFinding(
            'font-without-tounicode',
            PdfConformanceSeverity.violation,
            'The font $baseFont has no /ToUnicode map, so ${level.label} '
                'cannot guarantee its text can be extracted.',
            clause: 'ISO 19005-${level.part}:6.3.8',
            page: page,
          ));
        }
      }
      return;
    }

    await _checkFontDescriptor(font, baseFont, page, level, findings);

    if (!font.containsKey(CraftPdfName.widths)) {
      findings.add(PdfConformanceFinding(
        'font-without-widths',
        PdfConformanceSeverity.violation,
        'The font $baseFont has no /Widths array, so its metrics would come '
            'from the reader.',
        clause: 'ISO 19005-${level.part}:6.3.5',
        page: page,
      ));
    }
  }

  static Future<void> _checkFontDescriptor(
    CraftPdfDictionary font,
    String baseFont,
    int page,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final descriptor = await font.dictionaryEntry(CraftPdfName.fontDescriptor);
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
      return;
    }
    final embedded = descriptor.containsKey(CraftPdfName.fontFile) ||
        descriptor.containsKey(CraftPdfName.fontFile2) ||
        descriptor.containsKey(CraftPdfName.fontFile3);
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
  }

  static Future<void> _checkExtGState(
    CraftPdfDictionary state,
    int page,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    for (final key in const ['TR', 'TR2']) {
      if (state.containsKey(CraftPdfName(key))) {
        final value = await state.nameEntry(CraftPdfName(key));
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

    final softMask = await state.get(CraftPdfName('SMask'));
    if (softMask != null &&
        !(softMask.objectKind() == PdfObjectType.name &&
            (softMask as CraftPdfName).getValue() == 'None')) {
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
      final alpha = await state.decimalEntry(CraftPdfName(key));
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
    final blend = await state.nameEntry(CraftPdfName('BM'));
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
    CraftPdfStream xobject,
    int page,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final subtype = (await xobject.nameEntry(CraftPdfName.subtype))?.getValue();

    if (subtype == 'Image') {
      final interpolate = await xobject.flagEntry(CraftPdfName('Interpolate'));
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
      if (level.forbidsTransparency &&
          xobject.containsKey(CraftPdfName('SMask'))) {
        final mask = await xobject.nameEntry(CraftPdfName('SMask'));
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
    }

    if (subtype == 'Form' && level.forbidsTransparency) {
      final group = await xobject.dictionaryEntry(CraftPdfName('Group'));
      final groupType = await group?.nameEntry(CraftPdfName('S'));
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

    if (xobject.containsKey(CraftPdfName('PS')) || (subtype == 'PS')) {
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

  // --- object graph ---------------------------------------------------------

  static Future<void> _checkObjects(
    CraftPdfDocument document,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    if (!level.forbidsLzw) return;

    final xref = document.crossReferenceTable();
    var reported = 0;
    for (var number = 1; number < xref.size() && reported < 10; number++) {
      final reference = xref.get(number);
      if (reference == null || reference.isFree()) continue;
      CraftPdfObject? object;
      try {
        object = await reference.targetObject(true);
      } on Object {
        continue;
      }
      if (object == null || object.objectKind() != PdfObjectType.stream) {
        continue;
      }
      final stream = object as CraftPdfStream;
      if (await _usesFilter(stream, 'LZWDecode')) {
        findings.add(PdfConformanceFinding(
          'lzw-filter',
          PdfConformanceSeverity.violation,
          'A stream uses the LZWDecode filter, which ${level.label} does not '
              'permit.',
          clause: 'ISO 19005-${level.part}:6.1.10',
          objectNumber: number,
        ));
        reported++;
      }
      if (stream.containsKey(CraftPdfName('F'))) {
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

  static Future<bool> _usesFilter(CraftPdfStream stream, String name) async {
    final filter = await stream.get(CraftPdfName.filter);
    if (filter == null) return false;
    if (filter.objectKind() == PdfObjectType.name) {
      return (filter as CraftPdfName).getValue() == name;
    }
    if (filter.objectKind() == PdfObjectType.array) {
      final array = filter as CraftPdfArray;
      for (var i = 0; i < array.size(); i++) {
        if ((await array.nameEntry(i))?.getValue() == name) return true;
      }
    }
    return false;
  }
}
