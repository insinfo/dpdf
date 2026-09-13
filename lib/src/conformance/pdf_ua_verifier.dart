import 'dart:convert';
import 'dart:typed_data';

import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_page.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/reader_properties.dart';
import 'content_stream_scan.dart';
import 'finding_sink.dart';
import 'pdf_conformance.dart';
import 'pdf_conformance_report.dart';
import 'structure_scan.dart';
import 'xmp_identification.dart';

/// Checks an existing document against PDF/UA, the accessibility profile.
///
/// PDF/UA is largely about whether the structure tree says something true
/// about the page. This verifier settles the machine checkable half: the file
/// must be tagged, declare a language and a title, expose the title to the
/// reader, give every figure and link a text alternative, build its headings
/// as an outline that steps down one level at a time, build its tables as
/// grids whose headers say what they head, mark everything on the page as
/// either content or an artifact, and tie every page and annotation back to
/// the tree.
///
/// Judgements a person has to make — is the reading order right, does the
/// alternative text describe the picture, is the contrast sufficient — are
/// listed as unverified rather than quietly passed.
class PdfUAVerifier {
  PdfUAVerifier._();

  /// Verifies [bytes] against [level].
  static Future<PdfConformanceReport> verify(
    Uint8List bytes, {
    PdfUAConformanceLevel level = PdfUAConformanceLevel.ua1,
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

      if (claim.pdfUALevel == null) {
        findings.add(PdfConformanceFinding(
          'missing-pdfuaid',
          PdfConformanceSeverity.violation,
          'The XMP metadata does not identify the file as ${level.label}; '
              'pdfuaid:part is required.',
          clause: 'ISO 14289-1:5',
        ));
      } else if (claim.pdfUALevel != level) {
        findings.add(PdfConformanceFinding(
          'profile-mismatch',
          PdfConformanceSeverity.warning,
          'The document declares ${claim.pdfUALevel!.label} but is being '
              'checked against ${level.label}.',
          clause: 'ISO 14289-1:5',
        ));
      }

      await _checkTagging(catalog, findings);
      await _checkLanguage(catalog, findings);
      await _checkTitle(document, catalog, claim, findings);
      await _checkStructureTree(catalog, findings);
      await _checkPages(document, findings);

      return PdfConformanceReport(
        profile: level.label,
        claimedProfile: claim.pdfUALevel?.label,
        findings: findings.build(),
        unverifiedRules: _unverified,
      );
    } finally {
      reader.close();
    }
  }

  /// The rules this verifier does not settle, each with the reason it cannot.
  ///
  /// All three need the page as a person sees it. Nothing in the object graph
  /// says where a paragraph sits relative to a picture, what a picture is of,
  /// or how two colours look side by side — so a validator that claimed to
  /// decide them would be guessing, and a guess in an accessibility report is
  /// worse than an admission.
  static const List<String> _unverified = [
    'Whether the reading order recorded in the structure tree matches the '
        'order a reader would follow on the rendered page. The tree is '
        'checked for shape — heading nesting, table geometry, list '
        'composition, role mapping — but not against the layout.',
    'Whether an /Alt or /ActualText actually describes what it replaces. '
        'Their presence is checked; their aptness is a human judgement.',
    'Colour contrast, text size and any other judgement about how the page '
        'looks, which needs the page to be rendered.',
  ];

  static Future<void> _checkTagging(
    PdfDictionary catalog,
    FindingSink findings,
  ) async {
    final markInfo = await catalog.dictionaryEntry(PdfName.markInfo);
    if (markInfo == null) {
      findings.add(const PdfConformanceFinding(
        'missing-markinfo',
        PdfConformanceSeverity.violation,
        'The catalog has no /MarkInfo dictionary, so the file does not claim '
            'to be tagged.',
        clause: 'ISO 14289-1:7.1',
      ));
      return;
    }
    if (await markInfo.flagEntry(PdfName('Marked')) != true) {
      findings.add(const PdfConformanceFinding(
        'not-marked',
        PdfConformanceSeverity.violation,
        '/MarkInfo does not set /Marked true.',
        clause: 'ISO 14289-1:7.1',
      ));
    }
    if (await markInfo.flagEntry(PdfName('Suspects')) == true) {
      findings.add(const PdfConformanceFinding(
        'suspects',
        PdfConformanceSeverity.violation,
        '/MarkInfo sets /Suspects true, which says the tagging may not match '
            'the content.',
        clause: 'ISO 14289-1:7.1',
      ));
    }
  }

  static Future<void> _checkLanguage(
    PdfDictionary catalog,
    FindingSink findings,
  ) async {
    final lang = await catalog.stringEntry(PdfName('Lang'));
    final value = lang?.getValue();
    if (value == null || value.trim().isEmpty) {
      findings.add(const PdfConformanceFinding(
        'missing-lang',
        PdfConformanceSeverity.violation,
        'The catalog declares no /Lang, so a screen reader cannot choose a '
            'pronunciation for the text.',
        clause: 'ISO 14289-1:7.2',
      ));
    }
  }

  static Future<void> _checkTitle(
    PdfDocument document,
    PdfDictionary catalog,
    XmpIdentification claim,
    FindingSink findings,
  ) async {
    if (claim.title == null) {
      findings.add(const PdfConformanceFinding(
        'missing-title',
        PdfConformanceSeverity.violation,
        'The XMP metadata carries no dc:title, so the document has no name to '
            'announce.',
        clause: 'ISO 14289-1:7.1',
      ));
    }

    final preferences =
        await catalog.dictionaryEntry(PdfName('ViewerPreferences'));
    final displayTitle =
        await preferences?.flagEntry(PdfName('DisplayDocTitle'));
    if (displayTitle != true) {
      findings.add(const PdfConformanceFinding(
        'title-not-displayed',
        PdfConformanceSeverity.violation,
        'The catalog does not set /ViewerPreferences << /DisplayDocTitle true '
            '>>, so a reader shows the file name instead of the title.',
        clause: 'ISO 14289-1:7.1',
      ));
    }
  }

  static Future<void> _checkStructureTree(
    PdfDictionary catalog,
    FindingSink findings,
  ) async {
    final root = await catalog.dictionaryEntry(PdfName.structTreeRoot);
    if (root == null) {
      findings.add(const PdfConformanceFinding(
        'missing-structure-tree',
        PdfConformanceSeverity.violation,
        'The catalog has no /StructTreeRoot, so there is no logical structure '
            'to read.',
        clause: 'ISO 14289-1:7.1',
      ));
      return;
    }
    if (!root.containsKey(PdfName('K'))) {
      findings.add(const PdfConformanceFinding(
        'empty-structure-tree',
        PdfConformanceSeverity.violation,
        'The structure tree root has no /K children, so the tree is empty.',
        clause: 'ISO 14289-1:7.1',
      ));
      return;
    }

    final scan = await scanStructureTree(root);
    if (!scan.hasElements) {
      findings.add(const PdfConformanceFinding(
        'empty-structure-tree',
        PdfConformanceSeverity.violation,
        'The structure tree carries no elements, so it describes nothing.',
        clause: 'ISO 14289-1:7.1',
      ));
      return;
    }
    for (final issue in scan.issues) {
      findings.add(PdfConformanceFinding(
        issue.code,
        PdfConformanceSeverity.violation,
        issue.message,
        clause: issue.uaClause,
      ));
    }
  }

  static Future<void> _checkPages(
    PdfDocument document,
    FindingSink findings,
  ) async {
    final pageCount = document.pageHierarchy().pageTotal();
    for (var number = 1; number <= pageCount; number++) {
      final page = await document.pageAt(number);
      if (page == null) continue;
      final dictionary = page.pdfRepresentation();

      if (!dictionary.containsKey(PdfName('StructParents'))) {
        findings.add(PdfConformanceFinding(
          'page-without-structparents',
          PdfConformanceSeverity.violation,
          'The page has no /StructParents entry, so its marked content cannot '
              'be tied back to the structure tree.',
          clause: 'ISO 14289-1:7.1',
          page: number,
        ));
      }

      await _checkPageContent(page, number, findings);
      await _checkPageAnnotations(page, number, findings);
    }
  }

  /// Everything a page paints is either content, and then it belongs to the
  /// structure tree through an `/MCID`, or decoration, and then it is an
  /// artifact. A mark that is neither is invisible to a screen reader and
  /// unexplained to everyone else.
  static Future<void> _checkPageContent(
    PdfPage page,
    int number,
    FindingSink findings,
  ) async {
    final Uint8List content;
    try {
      content = await page.contentPayload();
    } on Object {
      return;
    }
    if (content.isEmpty) return;

    final resources =
        await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
    final scan = await scanContentStream(content, resources);
    if (!scan.parsed) {
      findings.add(PdfConformanceFinding(
        'content-stream-unparsable',
        PdfConformanceSeverity.violation,
        'The content stream is not valid PDF content: ${scan.failure}.',
        clause: 'ISO 14289-1:7.1',
        page: number,
      ));
      return;
    }

    if (scan.paintsOutsideMarkedContent) {
      findings.add(PdfConformanceFinding(
        'content-not-tagged',
        PdfConformanceSeverity.violation,
        'The page paints outside any marked-content sequence. Content has to '
            'sit inside a sequence that carries an /MCID, and decoration has '
            'to be marked /Artifact; anything else is unreachable from the '
            'structure tree and unexplained.',
        clause: 'ISO 14289-1:7.1',
        page: number,
      ));
    } else if (scan.paintsInUnidentifiedMarkedContent) {
      findings.add(PdfConformanceFinding(
        'marked-content-without-mcid',
        PdfConformanceSeverity.violation,
        'The page paints inside a marked-content sequence that is neither an '
            'artifact nor carries an /MCID, so the marks belong to no '
            'structure element.',
        clause: 'ISO 14289-1:7.1',
        page: number,
      ));
    }
    if (scan.unbalancedMarkedContent) {
      findings.add(PdfConformanceFinding(
        'unbalanced-marked-content',
        PdfConformanceSeverity.violation,
        'The page does not pair its BDC/BMC operators with EMC, so where one '
            'sequence ends and the next begins is undefined.',
        clause: 'ISO 14289-1:7.1',
        page: number,
      ));
    }
  }

  static Future<void> _checkPageAnnotations(
    PdfPage page,
    int number,
    FindingSink findings,
  ) async {
    final annotations =
        await page.pdfRepresentation().arrayEntry(PdfName.annots);
    if (annotations == null || annotations.size() == 0) return;

    // A page with annotations has a tab order, and a screen reader follows it.
    // Leaving it unset makes the order whatever the reader decides.
    final tabs = await page.pdfRepresentation().nameEntry(PdfName('Tabs'));
    if (tabs?.getValue() != 'S') {
      findings.add(PdfConformanceFinding(
        'page-without-structure-tab-order',
        PdfConformanceSeverity.violation,
        'The page carries annotations but does not set /Tabs /S, so the order '
            'a reader tabs through them in is not the order of the structure '
            'tree.',
        clause: 'ISO 14289-1:7.18.3',
        page: number,
      ));
    }

    for (var i = 0; i < annotations.size(); i++) {
      final annotation = await annotations.dictionaryEntry(i);
      if (annotation == null) continue;
      final subtype = (await annotation.nameEntry(PdfName.subtype))?.getValue();
      if (subtype == 'Popup') continue;

      final contents = await annotation.stringEntry(PdfName('Contents'));
      if (subtype == 'Link' && (contents?.getValue().trim().isEmpty ?? true)) {
        findings.add(PdfConformanceFinding(
          'link-without-description',
          PdfConformanceSeverity.violation,
          'A /Link annotation has no /Contents, so a screen reader announces '
              'a destination with no name.',
          clause: 'ISO 14289-1:7.18.5',
          page: number,
        ));
      }
      if (!annotation.containsKey(PdfName('StructParent'))) {
        findings.add(PdfConformanceFinding(
          'annotation-without-structparent',
          PdfConformanceSeverity.violation,
          'A /$subtype annotation has no /StructParent, so it is outside the '
              'structure tree.',
          clause: 'ISO 14289-1:7.18.1',
          page: number,
        ));
      }
    }
  }
}
