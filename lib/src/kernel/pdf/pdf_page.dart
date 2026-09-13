import 'dart:typed_data';

import '../geom/rectangle.dart';
import '../geom/page_size.dart';
import 'pdf_object.dart';
import 'pdf_dictionary.dart';
import 'pdf_array.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_stream.dart';
import 'pdf_object_wrapper.dart';
import 'pdf_resources.dart';
import 'pdf_pages.dart';
import 'annot/pdf_annotation.dart';
import 'viewer/pdf_transition.dart';
import 'viewer/pdf_page_piece.dart';
import 'viewer/pdf_measure.dart';
import 'article/pdf_bead.dart';
import '../exceptions/pdf_exception.dart';

/// Wrapper class that represents a page in a PDF document.
class PdfPage extends PdfObjectWrapper<PdfDictionary> {
  PdfResources? _resources;
  PdfPages? _parentPages;

  PdfPage(PdfDictionary pdfObject) : super(pdfObject) {
    pdfObject.put(PdfName.type, PdfName.page);
  }

  @override
  bool requiresIndirectStorage() => true;

  Future<PdfResources> resourceDirectory() async {
    if (_resources == null) {
      final resDict =
          await pdfRepresentation().dictionaryEntry(PdfName.resources);
      if (resDict != null) {
        _resources = PdfResources(resDict);
        await _resources!.init();
      } else {
        _resources = PdfResources();
        pdfRepresentation()
            .put(PdfName.resources, _resources!.pdfRepresentation());
      }
    }
    return _resources!;
  }

  /// Installs a page-local resource dictionary and refreshes the cached wrapper.
  void replaceResourceDirectory(PdfResources resources) {
    _resources = resources;
    pdfRepresentation().put(PdfName.resources, resources.pdfRepresentation());
    pdfRepresentation().markChanged();
  }

  PdfPages? get parentPages => _parentPages;
  set parentPages(PdfPages? value) => _parentPages = value;

  /// Gets the media box for this page.
  Future<Rectangle> mediaBounds() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.mediaBox);
    return array != null
        ? await Rectangle.fromPdfArray(array) ?? PageSize.defaultSize
        : PageSize.defaultSize;
  }

  /// Sets the media box for this page.
  void setMediaBounds(Rectangle rect) {
    pdfRepresentation().put(PdfName.mediaBox, rect.toPdfArray());
    pdfRepresentation().markChanged();
  }

  /// Gets the crop box for this page.
  Future<Rectangle> cropBounds() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.cropBox);
    if (array != null) {
      final rect = await Rectangle.fromPdfArray(array);
      if (rect != null) return rect;
    }
    return await mediaBounds();
  }

  /// Sets the crop box for this page.
  void setCropBounds(Rectangle rect) {
    pdfRepresentation().put(PdfName.cropBox, rect.toPdfArray());
    pdfRepresentation().markChanged();
  }

  /// Gets the rotation for this page.
  Future<int> rotationDegrees() async {
    final rotate = await pdfRepresentation().numberEntry(PdfName.rotate);
    return rotate != null ? rotate.intValue() % 360 : 0;
  }

  /// Sets the rotation for this page.
  void setRotationDegrees(int rotate) {
    pdfRepresentation().put(PdfName.rotate, PdfNumber.fromInt(rotate));
    pdfRepresentation().markChanged();
  }

  /// Gets the content stream at the specified index.
  Future<PdfObject?> contentSegmentAt(int index) async {
    final contents = await pdfRepresentation().get(PdfName.contents, true);
    if (contents is PdfStream) {
      return index == 0 ? contents : null;
    } else if (contents is PdfArray) {
      return await contents.get(index);
    }
    return null;
  }

  /// Gets the count of content streams.
  Future<int> contentSegmentCount() async {
    final contents = await pdfRepresentation().get(PdfName.contents, true);
    if (contents is PdfStream) {
      return 1;
    } else if (contents is PdfArray) {
      return contents.size();
    }
    return 0;
  }

  /// Adds an annotation to the page.
  Future<void> addAnnotation(PdfAnnotation annotation) async {
    PdfArray? annots = await pdfRepresentation().arrayEntry(PdfName.annots);
    if (annots == null) {
      annots = PdfArray();
      pdfRepresentation().put(PdfName.annots, annots);
    }
    annots.add(annotation.pdfRepresentation());
    annotation.setPage(this);

    // Mark page as modified for incremental updates (append mode)
    pdfRepresentation().markChanged();

    if (annotation.pdfRepresentation().isIndirectReference()) {
      // ensure indirect?
    } else {
      // if we want to ensure it is indirect, we should check/make it.
      // In , annotations are usually indirect.
    }
  }

  /// Gets the logical content of the page as a byte array.
  Future<Uint8List> contentPayload() async {
    final contents = await pdfRepresentation().get(PdfName.contents, true);
    if (contents is PdfStream) {
      return (await contents.getBytes()) ?? Uint8List(0);
    } else if (contents is PdfArray) {
      final buffer = <int>[];
      for (var i = 0; i < contents.size(); i++) {
        final content = await contents.get(i);
        if (content is PdfStream) {
          buffer.addAll((await content.getBytes()) ?? Uint8List(0));
          // Separate streams with whitespace if needed, PDF ref says concatenation.
          // Usually a whitespace or newline is safer to prevent operator merging.
          buffer.add(0x0A); // Newline
        }
      }
      return Uint8List.fromList(buffer);
    }
    return Uint8List(0);
  }

  /// Gets the next MCID for this page.
  Future<int> getNextMcid() async {
    final doc = getDocument();
    if (doc == null) return -1;
    return await doc.structureRoot().getNextMcidForPage(this);
  }

  /// Gets the StructParents entry for this page.
  Future<int?> getStructParents() async {
    return (await pdfRepresentation().numberEntry(PdfName.structParents))
        ?.intValue();
  }

  // =====================================================================
  // ISO 32000-1:2008, 12.4.4 Presentations - /Trans and /Dur (Table 30).
  // =====================================================================

  /// `/Dur`, the display duration of the page in a presentation.
  static final PdfName durationKey = PdfName.intern('Dur');

  /// Sets `/Trans`, the transition used when moving to this page during a
  /// presentation (12.4.4.1, Table 162).
  PdfPage setTransition(PdfTransition transition) {
    pdfRepresentation()
        .put(PdfTransition.trans, transition.pdfRepresentation());
    pdfRepresentation().markChanged();
    return this;
  }

  /// Gets `/Trans`, or `null` when the page defines no transition.
  Future<PdfTransition?> getTransition() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfTransition.trans);
    return dictionary == null ? null : PdfTransition.wrap(dictionary);
  }

  /// Removes `/Trans`.
  PdfPage removeTransition() {
    pdfRepresentation().remove(PdfTransition.trans);
    pdfRepresentation().markChanged();
    return this;
  }

  /// Sets `/Dur`, the maximum number of seconds the page is displayed before a
  /// presentation advances automatically. 12.4.4.1 gives no default: without
  /// the entry the page does not advance on its own, so a negative value is
  /// rejected.
  PdfPage setDisplayDuration(double seconds) {
    if (seconds < 0 || seconds.isNaN) {
      throw PdfException(
          '/Dur is a display duration in seconds and cannot be $seconds.');
    }
    pdfRepresentation().put(durationKey, PdfNumber(seconds));
    pdfRepresentation().markChanged();
    return this;
  }

  /// Gets `/Dur`, or `null` when the page does not advance automatically.
  Future<double?> getDisplayDuration() async {
    return (await pdfRepresentation().numberEntry(durationKey))?.doubleValue();
  }

  // =====================================================================
  // ISO 32000-1:2008, 12.4.3 Articles - /B, the beads on this page.
  // =====================================================================

  /// `/B`, the article beads appearing on this page, in drawing order.
  static final PdfName beadsKey = PdfName.intern('B');

  /// Appends [bead] to `/B`. 12.4.3 requires every page carrying article beads
  /// to list them, in drawing order, as indirect references.
  ///
  /// Beads are normally created through `PdfArticleThread.appendBead`, which
  /// calls this method itself.
  Future<void> addBead(PdfBead bead) async {
    var beads = await pdfRepresentation().arrayEntry(beadsKey);
    if (beads == null) {
      beads = PdfArray();
      pdfRepresentation().put(beadsKey, beads);
    }
    beads.add(bead.reference());
    beads.markChanged();
    pdfRepresentation().markChanged();
  }

  // =====================================================================
  // ISO 32000-1:2008, 12.9 Measurement properties - /VP (Table 30).
  // =====================================================================

  /// Appends [viewport] to `/VP` (PDF 1.6), the array of viewports of this
  /// page. 12.9 keeps that array in drawing order.
  Future<void> addViewport(PdfViewport viewport) async {
    await viewport.validate();
    var viewports =
        await pdfRepresentation().arrayEntry(PdfViewport.viewportsKey);
    if (viewports == null) {
      viewports = PdfArray();
      pdfRepresentation().put(PdfViewport.viewportsKey, viewports);
    }
    viewports.add(viewport.pdfRepresentation());
    viewports.markChanged();
    pdfRepresentation().markChanged();
  }

  /// Gets the viewports listed in `/VP`, in drawing order.
  Future<List<PdfViewport>> getViewports() async {
    final viewports =
        await pdfRepresentation().arrayEntry(PdfViewport.viewportsKey);
    if (viewports == null) return const [];
    final result = <PdfViewport>[];
    for (var index = 0; index < viewports.size(); index++) {
      final entry = await viewports.dictionaryEntry(index);
      if (entry != null) result.add(PdfViewport(entry));
    }
    return result;
  }

  /// Finds the viewport that governs the point `(x, y)` in default user space.
  ///
  /// 12.9 resolves overlapping viewports by examining `/VP` from its last entry
  /// backwards and choosing the first one whose `/BBox` contains the point.
  /// Returns `null` when no viewport covers it.
  Future<PdfViewport?> viewportAt(double x, double y) async {
    final viewports = await getViewports();
    for (var index = viewports.length - 1; index >= 0; index--) {
      if (await viewports[index].contains(x, y)) return viewports[index];
    }
    return null;
  }

  // =====================================================================
  // ISO 32000-1:2008, 14.5 Page-piece dictionaries - /PieceInfo (Table 30).
  // =====================================================================

  /// Gets `/PieceInfo`, the private data conforming products keep for this
  /// page (14.5, Table 318), or `null` when the page carries none.
  Future<PdfPagePiece?> getPieceInfo() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfPagePiece.pieceInfo);
    return dictionary == null ? null : PdfPagePiece(dictionary);
  }

  /// Gets `/PieceInfo`, creating and installing an empty page-piece dictionary
  /// when the page has none yet.
  Future<PdfPagePiece> pieceInfo() async {
    final existing = await getPieceInfo();
    if (existing != null) return existing;
    final created = PdfPagePiece();
    pdfRepresentation()
        .put(PdfPagePiece.pieceInfo, created.pdfRepresentation());
    pdfRepresentation().markChanged();
    return created;
  }

  /// Gets the beads listed in `/B`, in drawing order. An empty list means the
  /// page carries no article beads.
  Future<List<PdfBead>> getBeads() async {
    final beads = await pdfRepresentation().arrayEntry(beadsKey);
    if (beads == null) return const [];
    final result = <PdfBead>[];
    for (var index = 0; index < beads.size(); index++) {
      final entry = await beads.dictionaryEntry(index);
      if (entry != null) result.add(PdfBead(entry));
    }
    return result;
  }
}
