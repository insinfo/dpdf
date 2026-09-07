/// How badly a violation compromises the claimed profile.
enum PdfConformanceSeverity {
  /// The document does not meet the profile. A validator rejects it.
  violation,

  /// The document meets the letter of the profile but breaks a recommendation,
  /// or a rule this package can only partially verify.
  warning,

  /// An observation about what was checked; never a defect.
  info,
}

/// One rule the document was measured against.
class PdfConformanceFinding {
  /// Stable machine readable identifier, e.g. `font-not-embedded`. Message
  /// wording may change between releases; this code is the contract.
  final String code;

  final PdfConformanceSeverity severity;

  /// What was observed, in English.
  final String message;

  /// The clause of the standard the rule comes from, e.g. `ISO 19005-1:6.3.4`.
  final String clause;

  /// Page number the finding belongs to, when it is page scoped.
  final int? page;

  /// Object number the finding belongs to, when it is object scoped.
  final int? objectNumber;

  const PdfConformanceFinding(
    this.code,
    this.severity,
    this.message, {
    required this.clause,
    this.page,
    this.objectNumber,
  });

  @override
  String toString() {
    final where = page != null
        ? ' (page $page)'
        : objectNumber != null
            ? ' (object $objectNumber)'
            : '';
    return '[${severity.name}] $code ($clause): $message$where';
  }
}

/// The outcome of checking one document against one profile.
///
/// A report is a verification, not a certification: it lists the rules this
/// package can decide, and says in [unverifiedRules] which parts of the
/// standard it did not evaluate, so a caller never mistakes a clean report for
/// full validation by a certified tool.
class PdfConformanceReport {
  /// The profile the document was checked against, e.g. `PDF/A-2b`.
  final String profile;

  /// The profile the document claims in its XMP metadata, when it declares
  /// one. A document may be checked against a profile it does not claim.
  final String? claimedProfile;

  final List<PdfConformanceFinding> findings;

  /// Names of rule groups that were not evaluated, so the caller knows the
  /// limits of a passing result.
  final List<String> unverifiedRules;

  const PdfConformanceReport({
    required this.profile,
    required this.claimedProfile,
    required this.findings,
    required this.unverifiedRules,
  });

  /// True when no [PdfConformanceSeverity.violation] was recorded.
  ///
  /// This means "nothing this package checks is broken", not "certified
  /// conforming"; see [unverifiedRules].
  bool get isConforming =>
      !findings.any((f) => f.severity == PdfConformanceSeverity.violation);

  List<PdfConformanceFinding> get violations => findings
      .where((f) => f.severity == PdfConformanceSeverity.violation)
      .toList(growable: false);

  List<PdfConformanceFinding> get warnings => findings
      .where((f) => f.severity == PdfConformanceSeverity.warning)
      .toList(growable: false);

  Map<String, Object?> toJson() => {
        'profile': profile,
        'claimedProfile': claimedProfile,
        'conforming': isConforming,
        'unverifiedRules': unverifiedRules,
        'findings': [
          for (final f in findings)
            {
              'code': f.code,
              'severity': f.severity.name,
              'clause': f.clause,
              'message': f.message,
              if (f.page != null) 'page': f.page,
              if (f.objectNumber != null) 'object': f.objectNumber,
            }
        ],
      };

  @override
  String toString() => 'PdfConformanceReport($profile, '
      '${isConforming ? 'conforming' : '${violations.length} violation(s)'}, '
      '${findings.length} finding(s))';
}
