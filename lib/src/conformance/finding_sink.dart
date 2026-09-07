import 'pdf_conformance_report.dart';

/// Collects findings while collapsing the ones a reader would only read once.
///
/// A single unembedded font used on every page of a hundred-page document is
/// one defect, not a hundred. A validator that lists it a hundred times buries
/// the other defects, so this sink keeps the first [perCodeLimit] occurrences
/// of each rule and replaces the rest with one line saying how many there
/// were.
class FindingSink {
  /// How many occurrences of one rule are listed before summarising.
  final int perCodeLimit;

  final List<PdfConformanceFinding> _kept = [];
  final Map<String, int> _counts = {};

  FindingSink({this.perCodeLimit = 10});

  void add(PdfConformanceFinding finding) {
    final seen = (_counts[finding.code] ?? 0) + 1;
    _counts[finding.code] = seen;
    if (seen <= perCodeLimit) _kept.add(finding);
  }

  /// True when [code] was recorded at least once.
  bool contains(String code) => _counts.containsKey(code);

  /// The kept findings, followed by one summary per rule that was capped.
  List<PdfConformanceFinding> build() {
    final result = List<PdfConformanceFinding>.from(_kept);
    for (final entry in _counts.entries) {
      if (entry.value <= perCodeLimit) continue;
      final sample = _kept.firstWhere((f) => f.code == entry.key);
      result.add(PdfConformanceFinding(
        '${entry.key}-repeated',
        PdfConformanceSeverity.info,
        'The rule ${entry.key} was broken ${entry.value} times in total; the '
            'first $perCodeLimit occurrences are listed above.',
        clause: sample.clause,
      ));
    }
    return List.unmodifiable(result);
  }
}
