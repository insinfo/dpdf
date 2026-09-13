import '../../exceptions/pdf_exception.dart';
import '../pdf_array.dart';
import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';

/// Values of `/NonFullScreenPageMode` (ISO 32000-1:2008, Table 150).
enum PdfNonFullScreenPageMode {
  /// Neither document outline nor thumbnail images visible.
  useNone('UseNone'),

  /// Document outline visible.
  useOutlines('UseOutlines'),

  /// Thumbnail images visible.
  useThumbs('UseThumbs'),

  /// Optional content group panel visible.
  useOC('UseOC');

  const PdfNonFullScreenPageMode(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// Resolves a `/NonFullScreenPageMode` value, or `null` when unrecognized.
  static PdfNonFullScreenPageMode? fromPdfName(PdfName? name) {
    return _lookup(values, (v) => v.pdfName, name);
  }
}

/// Values of `/Direction`, the predominant reading order (Table 150).
enum PdfReadingDirection {
  /// Left to right.
  l2r('L2R'),

  /// Right to left, including vertical writing systems.
  r2l('R2L');

  const PdfReadingDirection(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// Resolves a `/Direction` value, or `null` when unrecognized.
  static PdfReadingDirection? fromPdfName(PdfName? name) {
    return _lookup(values, (v) => v.pdfName, name);
  }
}

/// Page boundaries usable by `/ViewArea`, `/ViewClip`, `/PrintArea` and
/// `/PrintClip` (Table 150, referring to Table 30 and 14.11.2).
enum PdfPageBoundary {
  /// `/MediaBox`.
  mediaBox('MediaBox'),

  /// `/CropBox`, the default for all four entries.
  cropBox('CropBox'),

  /// `/BleedBox`.
  bleedBox('BleedBox'),

  /// `/TrimBox`.
  trimBox('TrimBox'),

  /// `/ArtBox`.
  artBox('ArtBox');

  const PdfPageBoundary(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// Resolves a page boundary name, or `null` when unrecognized.
  static PdfPageBoundary? fromPdfName(PdfName? name) {
    return _lookup(values, (v) => v.pdfName, name);
  }
}

/// Values of `/PrintScaling` (PDF 1.6, Table 150).
enum PdfPrintScaling {
  /// No page scaling.
  none('None'),

  /// The conforming reader's default print scaling.
  appDefault('AppDefault');

  const PdfPrintScaling(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// Resolves a `/PrintScaling` value, or `null` when unrecognized.
  ///
  /// Table 150 states that an unrecognized value shall be treated as
  /// `AppDefault`, which [PdfViewerPreferences.getPrintScaling] implements.
  static PdfPrintScaling? fromPdfName(PdfName? name) {
    return _lookup(values, (v) => v.pdfName, name);
  }
}

/// Values of `/Duplex`, the paper handling option (PDF 1.7, Table 150).
enum PdfDuplex {
  /// Print single-sided.
  simplex('Simplex'),

  /// Duplex and flip on the short edge of the sheet.
  duplexFlipShortEdge('DuplexFlipShortEdge'),

  /// Duplex and flip on the long edge of the sheet.
  duplexFlipLongEdge('DuplexFlipLongEdge');

  const PdfDuplex(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// Resolves a `/Duplex` value, or `null` when unrecognized.
  static PdfDuplex? fromPdfName(PdfName? name) {
    return _lookup(values, (v) => v.pdfName, name);
  }
}

T? _lookup<T>(List<T> values, String Function(T) nameOf, PdfName? name) {
  if (name == null) return null;
  final value = name.getValue();
  for (final candidate in values) {
    if (nameOf(candidate) == value) return candidate;
  }
  return null;
}

/// The viewer preferences dictionary of ISO 32000-1:2008, 12.2, Table 150.
///
/// It controls the way the document is presented on the screen or in print and
/// is stored under `/ViewerPreferences` in the document catalog (Table 28).
/// Every entry is optional; the getters return the default value mandated by
/// Table 150 when the entry is absent.
class PdfViewerPreferences extends PdfObjectWrapper<PdfDictionary> {
  /// `/HideToolbar`.
  static final PdfName hideToolbar = PdfName.intern('HideToolbar');

  /// `/HideMenubar`.
  static final PdfName hideMenubar = PdfName.intern('HideMenubar');

  /// `/HideWindowUI`.
  static final PdfName hideWindowUI = PdfName.intern('HideWindowUI');

  /// `/FitWindow`.
  static final PdfName fitWindow = PdfName.intern('FitWindow');

  /// `/CenterWindow`.
  static final PdfName centerWindow = PdfName.intern('CenterWindow');

  /// `/DisplayDocTitle`.
  static final PdfName displayDocTitle = PdfName.intern('DisplayDocTitle');

  /// `/NonFullScreenPageMode`.
  static final PdfName nonFullScreenPageMode =
      PdfName.intern('NonFullScreenPageMode');

  /// `/Direction`.
  static final PdfName direction = PdfName.intern('Direction');

  /// `/ViewArea`.
  static final PdfName viewArea = PdfName.intern('ViewArea');

  /// `/ViewClip`.
  static final PdfName viewClip = PdfName.intern('ViewClip');

  /// `/PrintArea`.
  static final PdfName printArea = PdfName.intern('PrintArea');

  /// `/PrintClip`.
  static final PdfName printClip = PdfName.intern('PrintClip');

  /// `/PrintScaling`.
  static final PdfName printScaling = PdfName.intern('PrintScaling');

  /// `/Duplex`.
  static final PdfName duplex = PdfName.intern('Duplex');

  /// `/PickTrayByPDFSize`.
  static final PdfName pickTrayByPDFSize = PdfName.intern('PickTrayByPDFSize');

  /// `/PrintPageRange`.
  static final PdfName printPageRange = PdfName.intern('PrintPageRange');

  /// `/NumCopies`.
  static final PdfName numCopies = PdfName.intern('NumCopies');

  /// Wraps [dictionary], or starts an empty viewer preferences dictionary.
  PdfViewerPreferences([PdfDictionary? dictionary])
      : super(dictionary ?? PdfDictionary());

  /// Table 150 describes a plain dictionary, so it may stay a direct object.
  @override
  bool requiresIndirectStorage() => false;

  // ----------------------------------------------------------------- flags

  /// Sets `/HideToolbar`: hide the reader's tool bars. Default `false`.
  PdfViewerPreferences setHideToolbar(bool value) =>
      _putBoolean(hideToolbar, value);

  /// Gets `/HideToolbar`, defaulting to `false`.
  Future<bool> getHideToolbar() => _flag(hideToolbar);

  /// Sets `/HideMenubar`: hide the reader's menu bar. Default `false`.
  PdfViewerPreferences setHideMenubar(bool value) =>
      _putBoolean(hideMenubar, value);

  /// Gets `/HideMenubar`, defaulting to `false`.
  Future<bool> getHideMenubar() => _flag(hideMenubar);

  /// Sets `/HideWindowUI`: hide scroll bars and navigation controls.
  /// Default `false`.
  PdfViewerPreferences setHideWindowUI(bool value) =>
      _putBoolean(hideWindowUI, value);

  /// Gets `/HideWindowUI`, defaulting to `false`.
  Future<bool> getHideWindowUI() => _flag(hideWindowUI);

  /// Sets `/FitWindow`: resize the window to the first displayed page.
  /// Default `false`.
  PdfViewerPreferences setFitWindow(bool value) =>
      _putBoolean(fitWindow, value);

  /// Gets `/FitWindow`, defaulting to `false`.
  Future<bool> getFitWindow() => _flag(fitWindow);

  /// Sets `/CenterWindow`: centre the window on the screen. Default `false`.
  PdfViewerPreferences setCenterWindow(bool value) =>
      _putBoolean(centerWindow, value);

  /// Gets `/CenterWindow`, defaulting to `false`.
  Future<bool> getCenterWindow() => _flag(centerWindow);

  /// Sets `/DisplayDocTitle` (PDF 1.4): show the `/Title` of the document
  /// information dictionary in the window title bar. Default `false`.
  PdfViewerPreferences setDisplayDocTitle(bool value) =>
      _putBoolean(displayDocTitle, value);

  /// Gets `/DisplayDocTitle`, defaulting to `false`.
  Future<bool> getDisplayDocTitle() => _flag(displayDocTitle);

  /// Sets `/PickTrayByPDFSize` (PDF 1.7): use the PDF page size to select the
  /// input paper tray.
  PdfViewerPreferences setPickTrayByPDFSize(bool value) =>
      _putBoolean(pickTrayByPDFSize, value);

  /// Gets `/PickTrayByPDFSize`. Table 150 leaves the default to the conforming
  /// reader, so `null` is returned when the entry is absent.
  Future<bool?> getPickTrayByPDFSize() async {
    return (await pdfRepresentation().booleanEntry(pickTrayByPDFSize))
        ?.getValue();
  }

  // ----------------------------------------------------------------- names

  /// Sets `/NonFullScreenPageMode`, the page mode used on leaving full-screen
  /// mode. Meaningful only when the catalog's `/PageMode` is `/FullScreen`.
  PdfViewerPreferences setNonFullScreenPageMode(
          PdfNonFullScreenPageMode mode) =>
      _putName(nonFullScreenPageMode, mode.pdfName);

  /// Gets `/NonFullScreenPageMode`, defaulting to
  /// [PdfNonFullScreenPageMode.useNone].
  Future<PdfNonFullScreenPageMode> getNonFullScreenPageMode() async {
    return PdfNonFullScreenPageMode.fromPdfName(
            await pdfRepresentation().nameEntry(nonFullScreenPageMode)) ??
        PdfNonFullScreenPageMode.useNone;
  }

  /// Sets `/Direction` (PDF 1.3), the predominant reading order for text.
  PdfViewerPreferences setDirection(PdfReadingDirection value) =>
      _putName(direction, value.pdfName);

  /// Gets `/Direction`, defaulting to [PdfReadingDirection.l2r].
  Future<PdfReadingDirection> getDirection() async {
    return PdfReadingDirection.fromPdfName(
            await pdfRepresentation().nameEntry(direction)) ??
        PdfReadingDirection.l2r;
  }

  /// Sets `/ViewArea` (PDF 1.4), the page boundary displayed on screen.
  PdfViewerPreferences setViewArea(PdfPageBoundary boundary) =>
      _putName(viewArea, boundary.pdfName);

  /// Gets `/ViewArea`, defaulting to [PdfPageBoundary.cropBox].
  Future<PdfPageBoundary> getViewArea() => _boundary(viewArea);

  /// Sets `/ViewClip` (PDF 1.4), the page boundary clipping the screen view.
  PdfViewerPreferences setViewClip(PdfPageBoundary boundary) =>
      _putName(viewClip, boundary.pdfName);

  /// Gets `/ViewClip`, defaulting to [PdfPageBoundary.cropBox].
  Future<PdfPageBoundary> getViewClip() => _boundary(viewClip);

  /// Sets `/PrintArea` (PDF 1.4), the page boundary rendered when printing.
  PdfViewerPreferences setPrintArea(PdfPageBoundary boundary) =>
      _putName(printArea, boundary.pdfName);

  /// Gets `/PrintArea`, defaulting to [PdfPageBoundary.cropBox].
  Future<PdfPageBoundary> getPrintArea() => _boundary(printArea);

  /// Sets `/PrintClip` (PDF 1.4), the page boundary clipping printed output.
  PdfViewerPreferences setPrintClip(PdfPageBoundary boundary) =>
      _putName(printClip, boundary.pdfName);

  /// Gets `/PrintClip`, defaulting to [PdfPageBoundary.cropBox].
  Future<PdfPageBoundary> getPrintClip() => _boundary(printClip);

  /// Sets `/PrintScaling` (PDF 1.6), the page scaling option preselected in
  /// the print dialog.
  PdfViewerPreferences setPrintScaling(PdfPrintScaling scaling) =>
      _putName(printScaling, scaling.pdfName);

  /// Gets `/PrintScaling`. Table 150 requires an unrecognized value to be
  /// treated as [PdfPrintScaling.appDefault], which is also the default.
  Future<PdfPrintScaling> getPrintScaling() async {
    return PdfPrintScaling.fromPdfName(
            await pdfRepresentation().nameEntry(printScaling)) ??
        PdfPrintScaling.appDefault;
  }

  /// Sets `/Duplex` (PDF 1.7), the paper handling option.
  PdfViewerPreferences setDuplex(PdfDuplex value) =>
      _putName(duplex, value.pdfName);

  /// Gets `/Duplex`. Table 150 gives no default, so `null` is returned when
  /// the entry is absent or carries an unrecognized name.
  Future<PdfDuplex?> getDuplex() async {
    return PdfDuplex.fromPdfName(await pdfRepresentation().nameEntry(duplex));
  }

  // ------------------------------------------------------------- print job

  /// Sets `/PrintPageRange` (PDF 1.7) from a flat list of page numbers read in
  /// pairs, each pair giving the first and the last page of a sub-range.
  ///
  /// Table 150 requires an even number of integers and numbers the first page
  /// of the file 1, so an odd-sized list, a page number below 1 or a pair whose
  /// end precedes its start is rejected with a [PdfException].
  PdfViewerPreferences setPrintPageRange(List<int> pageNumbers) {
    if (pageNumbers.isEmpty || pageNumbers.length.isOdd) {
      throw PdfException(
          '/PrintPageRange shall contain a non empty even number of integers, '
          'got ${pageNumbers.length}.');
    }
    for (var i = 0; i < pageNumbers.length; i += 2) {
      final first = pageNumbers[i];
      final last = pageNumbers[i + 1];
      if (first < 1 || last < 1) {
        throw PdfException(
            '/PrintPageRange page numbers start at 1, got [$first $last].');
      }
      if (last < first) {
        throw PdfException(
            '/PrintPageRange sub-range [$first $last] ends before it starts.');
      }
    }
    pdfRepresentation().put(printPageRange, PdfArray.fromInts(pageNumbers));
    markChanged();
    return this;
  }

  /// Gets `/PrintPageRange` as a flat list of page numbers, or `null` when the
  /// entry is absent.
  Future<List<int>?> getPrintPageRange() async {
    final array = await pdfRepresentation().arrayEntry(printPageRange);
    if (array == null) return null;
    return await array.toIntArray();
  }

  /// Sets `/NumCopies` (PDF 1.7), the number of copies preselected in the print
  /// dialog. Fewer than one copy is out of range and is rejected.
  PdfViewerPreferences setNumCopies(int copies) {
    if (copies < 1) {
      throw PdfException('/NumCopies shall be at least 1, got $copies.');
    }
    pdfRepresentation().put(numCopies, PdfNumber.fromInt(copies));
    markChanged();
    return this;
  }

  /// Gets `/NumCopies`, or `null` when the entry is absent. Table 150 leaves
  /// the default to the conforming reader, typically 1.
  Future<int?> getNumCopies() async {
    return (await pdfRepresentation().numberEntry(numCopies))?.intValue();
  }

  // ------------------------------------------------------------------ misc

  /// Puts an arbitrary entry, for viewer preferences outside Table 150.
  PdfViewerPreferences put(PdfName key, PdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
    return this;
  }

  /// Removes an entry, restoring its Table 150 default behaviour.
  PdfViewerPreferences remove(PdfName key) {
    pdfRepresentation().remove(key);
    markChanged();
    return this;
  }

  PdfViewerPreferences _putBoolean(PdfName key, bool value) {
    pdfRepresentation().put(key, PdfBoolean(value));
    markChanged();
    return this;
  }

  PdfViewerPreferences _putName(PdfName key, String value) {
    pdfRepresentation().put(key, PdfName.intern(value));
    markChanged();
    return this;
  }

  Future<bool> _flag(PdfName key) async {
    return (await pdfRepresentation().booleanEntry(key))?.getValue() ?? false;
  }

  Future<PdfPageBoundary> _boundary(PdfName key) async {
    return PdfPageBoundary.fromPdfName(
            await pdfRepresentation().nameEntry(key)) ??
        PdfPageBoundary.cropBox;
  }
}
