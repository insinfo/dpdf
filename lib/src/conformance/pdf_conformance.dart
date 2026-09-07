/// The archival profile a document claims or is checked against.
///
/// The letter suffix is the conformance level defined by the standard:
/// `b` (basic) guarantees visual reproduction, `u` additionally requires every
/// glyph to map to Unicode, and `a` (accessible) additionally requires a
/// logical structure tree.
enum PdfAConformanceLevel {
  a1b('1', 'B'),
  a1a('1', 'A'),
  a2b('2', 'B'),
  a2u('2', 'U'),
  a2a('2', 'A'),
  a3b('3', 'B'),
  a3u('3', 'U'),
  a3a('3', 'A'),
  a4('4', null),
  a4e('4', 'E'),
  a4f('4', 'F');

  /// The `pdfaid:part` value, e.g. `2` for PDF/A-2b.
  final String part;

  /// The `pdfaid:conformance` value, e.g. `B`. PDF/A-4 drops the entry, and
  /// uses `pdfaid:rev` plus an optional `E`/`F` flavour instead.
  final String? conformance;

  const PdfAConformanceLevel(this.part, this.conformance);

  /// The human readable name used by the standard, e.g. `PDF/A-2b`.
  String get label =>
      'PDF/A-$part${conformance == null ? '' : conformance!.toLowerCase()}';

  /// The highest PDF version the profile permits.
  ///
  /// PDF/A-1 is built on PDF 1.4, PDF/A-2 and PDF/A-3 on PDF 1.7, and PDF/A-4
  /// on PDF 2.0.
  String get maximumPdfVersion => switch (part) {
        '1' => '1.4',
        '2' || '3' => '1.7',
        _ => '2.0',
      };

  /// True when the profile requires a tagged logical structure.
  bool get requiresTagging => conformance == 'A';

  /// True when the profile requires every glyph to map to Unicode.
  bool get requiresUnicodeMapping => conformance == 'A' || conformance == 'U';

  /// True when the profile permits embedded file attachments.
  ///
  /// PDF/A-1 and PDF/A-2 forbid them; PDF/A-3 introduced them, and PDF/A-4
  /// keeps them (with `f` denoting a file that carries one).
  bool get allowsEmbeddedFiles => part == '3' || part == '4';

  /// True when the profile forbids any transparency.
  ///
  /// Only PDF/A-1, built on PDF 1.4, does.
  bool get forbidsTransparency => part == '1';

  /// True when the profile forbids `LZWDecode` as a stream filter.
  bool get forbidsLzw => part == '1' || part == '2' || part == '3';

  /// Parses a `pdfaid` pair, e.g. `('2', 'B')`. Returns null when the pair
  /// does not name a profile this package knows.
  static PdfAConformanceLevel? fromIdentifier(
      String part, String? conformance) {
    final normalized = conformance?.trim().toUpperCase();
    for (final level in PdfAConformanceLevel.values) {
      if (level.part == part.trim() && level.conformance == normalized) {
        return level;
      }
    }
    return null;
  }
}

/// The accessibility profile a document claims or is checked against.
enum PdfUAConformanceLevel {
  ua1('1'),
  ua2('2');

  /// The `pdfuaid:part` value.
  final String part;

  const PdfUAConformanceLevel(this.part);

  String get label => 'PDF/UA-$part';
}
