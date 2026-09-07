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

  static Future<void> _checkOutputIntents(
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
      return;
    }

    var seenPdfA = false;
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
  }

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

    final openAction = await catalog.get(PdfName('OpenAction'));
    if (openAction != null &&
        openAction.objectKind() == PdfObjectType.dictionary) {
      await _checkAction(openAction as PdfDictionary, level, findings);
    }
  }

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
    if (!catalog.containsKey(PdfName.structTreeRoot)) {
      findings.add(PdfConformanceFinding(
        'missing-structure-tree',
        PdfConformanceSeverity.violation,
        '${level.label} requires a /StructTreeRoot describing the logical '
            'structure.',
        clause: 'ISO 19005-${level.part}:6.8.2',
      ));
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

  static Future<void> _checkPages(
    PdfDocument document,
    PdfAConformanceLevel level,
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
      await _checkPageResources(page, number, level, findings);
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
  }

  static Future<void> _checkPageResources(
    PdfPage page,
    int number,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final resources =
        await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
    if (resources == null) return;

    final fonts = await resources.dictionaryEntry(PdfName.font);
    if (fonts != null) {
      for (final key in fonts.keySet()) {
        final font = await fonts.dictionaryEntry(key);
        if (font != null) {
          await _checkFont(font, number, level, findings);
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
    PdfDictionary font,
    int page,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    final subtype = (await font.nameEntry(PdfName.subtype))?.getValue();
    final baseFont =
        (await font.nameEntry(PdfName.baseFont))?.getValue() ?? 'unnamed';

    if (subtype == 'Type3') {
      // A Type 3 font carries its glyphs as content streams, so there is
      // nothing to embed; its charprocs are covered by the content stream
      // rules this verifier does not evaluate.
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
      await _checkFontDescriptor(descendant, baseFont, page, level, findings);
      if (level.requiresUnicodeMapping &&
          !font.containsKey(PdfName('ToUnicode'))) {
        final encoding = (await font.nameEntry(PdfName.encoding))?.getValue();
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

    if (!font.containsKey(PdfName.widths)) {
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
      return;
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
  }

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

  // --- object graph ---------------------------------------------------------

  static Future<void> _checkObjects(
    PdfDocument document,
    PdfAConformanceLevel level,
    FindingSink findings,
  ) async {
    if (!level.forbidsLzw) return;

    final xref = document.crossReferenceTable();
    var reported = 0;
    for (var number = 1; number < xref.size() && reported < 10; number++) {
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

  static Future<bool> _usesFilter(PdfStream stream, String name) async {
    final filter = await stream.get(PdfName.filter);
    if (filter == null) return false;
    if (filter.objectKind() == PdfObjectType.name) {
      return (filter as PdfName).getValue() == name;
    }
    if (filter.objectKind() == PdfObjectType.array) {
      final array = filter as PdfArray;
      for (var i = 0; i < array.size(); i++) {
        if ((await array.nameEntry(i))?.getValue() == name) return true;
      }
    }
    return false;
  }
}
