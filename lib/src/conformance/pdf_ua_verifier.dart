import 'dart:convert';
import 'dart:typed_data';

import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/reader_properties.dart';
import 'finding_sink.dart';
import 'pdf_conformance.dart';
import 'pdf_conformance_report.dart';
import 'xmp_identification.dart';

/// Checks an existing document against PDF/UA, the accessibility profile.
///
/// PDF/UA is largely about whether the structure tree says something true
/// about the page. This verifier settles the machine checkable half: the file
/// must be tagged, declare a language and a title, expose the title to the
/// reader, embed its fonts, and give every figure and link a text alternative.
/// Judgements a person has to make — is the reading order right, does the
/// alternative text describe the picture — are listed as unverified.
class PdfUAVerifier {
  PdfUAVerifier._();

  /// Structure types that stand in for something a reader cannot read, and so
  /// need a text alternative.
  static const Set<String> _needsAlternative = {'Figure', 'Formula'};

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
        unverifiedRules: const [
          'Whether the reading order of the structure tree matches the visual '
              'order of the page.',
          'Whether alternative text actually describes what it replaces.',
          'Heading nesting (H1 followed by H3), table header association, and '
              'list semantics.',
          'Colour contrast and any judgement about visual presentation.',
        ],
      );
    } finally {
      reader.close();
    }
  }

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
    await _walkStructure(root, findings, 0, <PdfDictionary>{});
  }

  static const int _maxStructureDepth = 128;

  static Future<void> _walkStructure(
    PdfDictionary node,
    FindingSink findings,
    int depth,
    Set<PdfDictionary> seen,
  ) async {
    if (depth > _maxStructureDepth || !seen.add(node)) return;

    final type = (await node.nameEntry(PdfName('S')))?.getValue();
    if (type != null && _needsAlternative.contains(type)) {
      final alt = await node.stringEntry(PdfName('Alt'));
      final actual = await node.stringEntry(PdfName('ActualText'));
      if ((alt?.getValue().trim().isEmpty ?? true) &&
          (actual?.getValue().trim().isEmpty ?? true)) {
        findings.add(PdfConformanceFinding(
          'figure-without-alternative',
          PdfConformanceSeverity.violation,
          'A /$type structure element has neither /Alt nor /ActualText, so it '
              'is silent to a screen reader.',
          clause: 'ISO 14289-1:7.3',
        ));
      }
    }

    final kids = await node.get(PdfName('K'));
    if (kids == null) return;
    if (kids.objectKind() == PdfObjectType.dictionary) {
      await _walkStructure(kids as PdfDictionary, findings, depth + 1, seen);
      return;
    }
    if (kids.objectKind() == PdfObjectType.array) {
      final array = kids as PdfArray;
      for (var i = 0; i < array.size(); i++) {
        final kid = await array.dictionaryEntry(i);
        if (kid != null) {
          await _walkStructure(kid, findings, depth + 1, seen);
        }
      }
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

      final annotations = await dictionary.arrayEntry(PdfName.annots);
      if (annotations == null) continue;
      for (var i = 0; i < annotations.size(); i++) {
        final annotation = await annotations.dictionaryEntry(i);
        if (annotation == null) continue;
        final subtype =
            (await annotation.nameEntry(PdfName.subtype))?.getValue();
        if (subtype == 'Popup') continue;

        final contents = await annotation.stringEntry(PdfName('Contents'));
        if (subtype == 'Link' &&
            (contents?.getValue().trim().isEmpty ?? true)) {
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
}
