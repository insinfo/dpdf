import '../../geom/rectangle.dart';
import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_page.dart';

/// The five page boundaries of ISO 32000-1:2008, 14.11.2 "Page Boundaries".
///
/// The order of the enumeration is the order in which the boxes nest in
/// Figure 86: the art box is the innermost, the media box the outermost.
enum PdfPageBox {
  /// `/MediaBox`, the physical medium (Table 30; required, inheritable).
  media,

  /// `/CropBox`, the clipping region (Table 30; optional, inheritable).
  /// Default value: the media box.
  crop,

  /// `/BleedBox` (PDF 1.3). Default value: the crop box.
  bleed,

  /// `/TrimBox` (PDF 1.3). Default value: the crop box.
  trim,

  /// `/ArtBox` (PDF 1.3). Default value: the crop box.
  art,
}

/// The `/MediaBox`, `/CropBox`, `/BleedBox`, `/TrimBox` and `/ArtBox` entries
/// of a page object.
///
/// Implements ISO 32000-1:2008, 14.11.2 "Page Boundaries" over the page
/// dictionary entries of Table 30:
///
/// * `/MediaBox` and `/CropBox` are inheritable, so a missing entry is looked
///   up through the `/Parent` chain of the page tree;
/// * `/CropBox` defaults to `/MediaBox`, and `/BleedBox`, `/TrimBox` and
///   `/ArtBox` default to `/CropBox`;
/// * "The crop, bleed, trim, and art boxes shall not ordinarily extend beyond
///   the boundaries of the media box. If they do, they are effectively reduced
///   to their intersection with the media box" - that reduction is what
///   [effectiveBox] returns, while [declaredBox] reports what is written.
class PdfPageBoundaries {
  /// `/MediaBox`.
  static final PdfName mediaBox = PdfName.intern('MediaBox');

  /// `/CropBox`.
  static final PdfName cropBox = PdfName.intern('CropBox');

  /// `/BleedBox`, PDF 1.3.
  static final PdfName bleedBox = PdfName.intern('BleedBox');

  /// `/TrimBox`, PDF 1.3.
  static final PdfName trimBox = PdfName.intern('TrimBox');

  /// `/ArtBox`, PDF 1.3.
  static final PdfName artBox = PdfName.intern('ArtBox');

  /// The maximum depth the `/Parent` chain is followed while resolving an
  /// inheritable entry; it also breaks cycles in a damaged page tree.
  static const int _maxInheritanceDepth = 64;

  final PdfDictionary _page;

  /// Wraps the dictionary of a page object.
  PdfPageBoundaries(this._page);

  /// Wraps the dictionary of [page].
  PdfPageBoundaries.ofPage(PdfPage page) : _page = page.pdfRepresentation();

  /// The wrapped page dictionary.
  PdfDictionary pageDictionary() => _page;

  /// The dictionary key of [box] as named in Table 30.
  static PdfName keyOf(PdfPageBox box) {
    switch (box) {
      case PdfPageBox.media:
        return mediaBox;
      case PdfPageBox.crop:
        return cropBox;
      case PdfPageBox.bleed:
        return bleedBox;
      case PdfPageBox.trim:
        return trimBox;
      case PdfPageBox.art:
        return artBox;
    }
  }

  /// Whether [box] is an inheritable page attribute.
  ///
  /// Only `/MediaBox` and `/CropBox` are marked inheritable in Table 30; the
  /// three PDF 1.3 boxes are not.
  static bool isInheritable(PdfPageBox box) =>
      box == PdfPageBox.media || box == PdfPageBox.crop;

  /// Writes [box].
  ///
  /// A rectangle with a negative width or height is rejected: 7.9.5 requires
  /// the pair of diagonally opposite corners, and every consumer of these
  /// boxes assumes the normalised form produced by [Rectangle.toPdfArray].
  void setBox(PdfPageBox box, Rectangle rectangle) {
    if (rectangle.getWidth() < 0 || rectangle.getHeight() < 0) {
      throw ArgumentError.value(rectangle, 'rectangle',
          'A page boundary shall have a non-negative width and height');
    }
    _page.put(keyOf(box), rectangle.toPdfArray());
    _page.markChanged();
  }

  /// Removes [box] from the page dictionary, restoring its default value.
  ///
  /// `/MediaBox` is required by Table 30, so removing it is refused.
  void removeBox(PdfPageBox box) {
    if (box == PdfPageBox.media) {
      throw ArgumentError.value(
          box, 'box', 'The /MediaBox entry is required by Table 30');
    }
    _page.remove(keyOf(box));
    _page.markChanged();
  }

  /// Whether [box] is written on this page dictionary itself.
  bool hasOwnBox(PdfPageBox box) => _page.containsKey(keyOf(box));

  /// The value of [box] exactly as it is written, without applying any default.
  ///
  /// Inheritable boxes are resolved through the `/Parent` chain; `null` means
  /// no ancestor carries the entry either.
  Future<Rectangle?> declaredBox(PdfPageBox box) async {
    final key = keyOf(box);
    if (!isInheritable(box)) {
      return Rectangle.fromPdfArray(await _page.arrayEntry(key));
    }
    var current = _page;
    for (var depth = 0; depth < _maxInheritanceDepth; depth++) {
      final array = await current.arrayEntry(key);
      if (array != null) {
        final rectangle = await Rectangle.fromPdfArray(array);
        if (rectangle != null) return rectangle;
      }
      final parent = await current.dictionaryEntry(PdfName.parent);
      if (parent == null || identical(parent, current)) return null;
      current = parent;
    }
    return null;
  }

  /// The value of [box] after the defaults of Table 30 are applied, but before
  /// the intersection with the media box of 14.11.2.1.
  ///
  /// Returns `null` only when the page has no media box at all, in which case
  /// none of the five boundaries can be determined.
  Future<Rectangle?> resolvedBox(PdfPageBox box) async {
    final media = await declaredBox(PdfPageBox.media);
    if (media == null) return null;
    if (box == PdfPageBox.media) return media;

    final crop = await declaredBox(PdfPageBox.crop) ?? media;
    if (box == PdfPageBox.crop) return crop;

    return await declaredBox(box) ?? crop;
  }

  /// The value of [box] as a conforming reader shall use it.
  ///
  /// 14.11.2.1: the crop, bleed, trim and art boxes "shall not ordinarily
  /// extend beyond the boundaries of the media box. If they do, they are
  /// effectively reduced to their intersection with the media box." A box that
  /// does not meet the media box at all yields an empty rectangle anchored at
  /// the intersection corner rather than `null`.
  Future<Rectangle?> effectiveBox(PdfPageBox box) async {
    final resolved = await resolvedBox(box);
    if (resolved == null) return null;
    if (box == PdfPageBox.media) return resolved;
    final media = await declaredBox(PdfPageBox.media);
    if (media == null) return null;
    return intersect(resolved, media);
  }

  /// The intersection of [a] and [b], clamped to a non-negative extent.
  static Rectangle intersect(Rectangle a, Rectangle b) {
    final left = a.getLeft() > b.getLeft() ? a.getLeft() : b.getLeft();
    final bottom =
        a.getBottom() > b.getBottom() ? a.getBottom() : b.getBottom();
    final right = a.getRight() < b.getRight() ? a.getRight() : b.getRight();
    final top = a.getTop() < b.getTop() ? a.getTop() : b.getTop();
    final width = right - left;
    final height = top - bottom;
    return Rectangle(
        left, bottom, width < 0 ? 0 : width, height < 0 ? 0 : height);
  }

  /// Whether [inner] lies inside [outer], allowing for [Rectangle.EPS] of
  /// rounding slack on each edge.
  static bool contains(Rectangle outer, Rectangle inner) =>
      inner.getLeft() >= outer.getLeft() - Rectangle.EPS &&
      inner.getBottom() >= outer.getBottom() - Rectangle.EPS &&
      inner.getRight() <= outer.getRight() + Rectangle.EPS &&
      inner.getTop() <= outer.getTop() + Rectangle.EPS;

  /// Copies every boundary written on [source] onto this page.
  Future<void> copyFrom(PdfPageBoundaries source) async {
    for (final box in PdfPageBox.values) {
      final key = keyOf(box);
      final array = await source._page.arrayEntry(key);
      if (array == null) continue;
      final rectangle = await Rectangle.fromPdfArray(array);
      if (rectangle != null) setBox(box, rectangle);
    }
  }

  /// Reports every way in which the page's boundaries depart from 14.11.2.
  ///
  /// The returned list is empty for a conforming page. Two kinds of problem
  /// are reported:
  ///
  /// * a missing or malformed `/MediaBox`, or a boundary array that is not a
  ///   well formed rectangle - these violate Table 30 and 7.9.5;
  /// * a crop, bleed, trim or art box that extends beyond the media box - the
  ///   spec calls this out of the ordinary and reduces it to the intersection,
  ///   so it is reported rather than thrown.
  ///
  /// Set [requireFigure86Nesting] to also require the nesting drawn in
  /// Figure 86, art box inside trim box inside bleed box. That nesting is
  /// illustrative rather than normative, so it is off by default.
  Future<List<String>> validate({bool requireFigure86Nesting = false}) async {
    final problems = <String>[];

    for (final box in PdfPageBox.values) {
      final array = await _page.arrayEntry(keyOf(box));
      if (array == null) continue;
      if (array.size() != 4) {
        problems.add('/${keyOf(box).getValue()} shall be an array of four '
            'numbers (7.9.5), found ${array.size()}');
        continue;
      }
      if (!await _isNumberArray(array)) {
        problems.add(
            '/${keyOf(box).getValue()} shall contain numbers only (7.9.5)');
      }
    }

    final media = await declaredBox(PdfPageBox.media);
    if (media == null) {
      problems.add('/MediaBox is required by Table 30 and was not found on the '
          'page or on any ancestor');
      return problems;
    }
    if (media.getWidth() <= 0 || media.getHeight() <= 0) {
      problems.add('/MediaBox shall enclose a non-empty area');
    }

    for (final box in PdfPageBox.values) {
      if (box == PdfPageBox.media) continue;
      final resolved = await resolvedBox(box);
      if (resolved == null) continue;
      if (!contains(media, resolved)) {
        problems.add('/${keyOf(box).getValue()} extends beyond /MediaBox and '
            'is effectively reduced to their intersection (14.11.2.1)');
      }
    }

    if (requireFigure86Nesting) {
      final bleed = await resolvedBox(PdfPageBox.bleed);
      final trim = await resolvedBox(PdfPageBox.trim);
      final art = await resolvedBox(PdfPageBox.art);
      if (bleed != null && trim != null && !contains(bleed, trim)) {
        problems.add('/TrimBox is not contained in /BleedBox (Figure 86)');
      }
      if (trim != null && art != null && !contains(trim, art)) {
        problems.add('/ArtBox is not contained in /TrimBox (Figure 86)');
      }
    }

    return problems;
  }

  static Future<bool> _isNumberArray(PdfArray array) async {
    for (var i = 0; i < array.size(); i++) {
      if (await array.numberEntry(i) == null) return false;
    }
    return true;
  }
}
