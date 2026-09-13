import '../pdf_name.dart';

/// Values of the catalog's `/PageLayout` entry (ISO 32000-1:2008, Table 28),
/// the layout used when the document is opened.
enum PdfPageLayout {
  /// Display one page at a time. The Table 28 default.
  singlePage('SinglePage'),

  /// Display the pages in one column.
  oneColumn('OneColumn'),

  /// Display the pages in two columns, odd-numbered pages on the left.
  twoColumnLeft('TwoColumnLeft'),

  /// Display the pages in two columns, odd-numbered pages on the right.
  twoColumnRight('TwoColumnRight'),

  /// (PDF 1.5) Display the pages two at a time, odd-numbered on the left.
  twoPageLeft('TwoPageLeft'),

  /// (PDF 1.5) Display the pages two at a time, odd-numbered on the right.
  twoPageRight('TwoPageRight');

  const PdfPageLayout(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// The `/PageLayout` value as a PDF name object.
  PdfName toPdfName() => PdfName.intern(pdfName);

  /// Resolves a `/PageLayout` value, or `null` when unrecognized.
  static PdfPageLayout? fromPdfName(PdfName? name) {
    if (name == null) return null;
    final value = name.getValue();
    for (final candidate in values) {
      if (candidate.pdfName == value) return candidate;
    }
    return null;
  }
}

/// Values of the catalog's `/PageMode` entry (ISO 32000-1:2008, Table 28),
/// specifying how the document is displayed when opened.
enum PdfPageMode {
  /// Neither document outline nor thumbnail images visible. The default.
  useNone('UseNone'),

  /// Document outline visible.
  useOutlines('UseOutlines'),

  /// Thumbnail images visible.
  useThumbs('UseThumbs'),

  /// Full-screen mode, with no menu bar, window controls or any other window.
  fullScreen('FullScreen'),

  /// (PDF 1.5) Optional content group panel visible.
  useOC('UseOC'),

  /// (PDF 1.6) Attachments panel visible.
  useAttachments('UseAttachments');

  const PdfPageMode(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// The `/PageMode` value as a PDF name object.
  PdfName toPdfName() => PdfName.intern(pdfName);

  /// Resolves a `/PageMode` value, or `null` when unrecognized.
  static PdfPageMode? fromPdfName(PdfName? name) {
    if (name == null) return null;
    final value = name.getValue();
    for (final candidate in values) {
      if (candidate.pdfName == value) return candidate;
    }
    return null;
  }
}
