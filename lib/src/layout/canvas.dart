import 'package:dpdf/src/layout/root_element.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/pdf_page.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/xobject/pdf_form_x_object.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/renderer/root_renderer.dart';
import 'package:dpdf/src/layout/renderer/canvas_renderer.dart';

/// Places layout elements inside an arbitrary rectangle of a content stream.
///
/// Unlike a [Document], a canvas never creates new areas: content that does not
/// fit in [rootArea] is rejected by the renderer.
class Canvas extends RootElement<Canvas> {
  PdfCanvas? pdfCanvas;
  Rectangle? rootArea;
  PdfPage? page;
  bool isCanvasOfPage = false;

  Canvas(PdfCanvas pdfCanvas, Rectangle rootArea, [bool immediateFlush = true])
      : super(pdfCanvas.getDocument()!) {
    this.pdfCanvas = pdfCanvas;
    this.rootArea = rootArea;
    this.immediateFlush = immediateFlush;
  }

  /// Creates a canvas drawing on [page], restricted to [rootArea] (the whole
  /// media box when omitted).
  static Future<Canvas> fromPage(PdfPage page, [Rectangle? rootArea]) async {
    final pdfCanvas = await PdfCanvas.fromPage(page);
    final canvas = Canvas(pdfCanvas, rootArea ?? (await page.mediaBounds()));
    canvas.page = page;
    canvas.isCanvasOfPage = true;
    return canvas;
  }

  /// Creates a canvas drawing into a form XObject, using its bounding box as
  /// the root area (ISO 32000-1, 8.10 "Form XObjects").
  static Future<Canvas> fromFormXObject(
      PdfFormXObject formXObject, PdfDocument document,
      [bool immediateFlush = true]) async {
    final resources = await formXObject.resourceDirectory();
    final pdfCanvas =
        PdfCanvas(formXObject.pdfRepresentation(), resources, document);
    final bbox = await formXObject.getBBox() ?? Rectangle(0, 0, 0, 0);
    return Canvas(pdfCanvas, bbox, immediateFlush);
  }

  /// Creates a canvas drawing on an existing [PdfCanvas] and covering the whole
  /// area of [rootArea].
  static Canvas fromPdfCanvas(PdfCanvas pdfCanvas, Rectangle rootArea,
          [bool immediateFlush = true]) =>
      Canvas(pdfCanvas, rootArea, immediateFlush);

  @override
  RootRenderer ensureRootRendererNotNull() {
    rootRenderer ??= CanvasRenderer(this, immediateFlush);
    return rootRenderer!;
  }

  /// Replaces the renderer used to place the content of this canvas.
  Canvas setRenderer(CanvasRenderer canvasRenderer) {
    rootRenderer = canvasRenderer;
    return this;
  }

  CanvasRenderer? getRenderer() => rootRenderer as CanvasRenderer?;

  /// Renders everything that is still waiting to be drawn.
  Future<void> flush() async {
    await ensureRootRendererNotNull().flush();
  }

  /// Relocates the root area, which is only meaningful before any content has
  /// been added.
  Canvas setRootArea(Rectangle rootArea) {
    this.rootArea = rootArea;
    return this;
  }

  @override
  Future<void> close() async {
    if (rootRenderer != null) {
      await rootRenderer!.close();
    }
  }

  PdfDocument getPdfDocument() {
    return pdfDocument;
  }

  PdfCanvas getPdfCanvas() {
    return pdfCanvas!;
  }

  PdfPage? pageAt() {
    return page;
  }

  bool getIsCanvasOfPage() {
    return isCanvasOfPage;
  }

  Rectangle? getRootArea() {
    return rootArea;
  }

  /// Enables margin collapsing (CSS 2.1, 8.3.1) for everything placed on this
  /// canvas.
  Canvas setCollapsingMargins(bool collapsingMargins) {
    setProperty(Property.COLLAPSING_MARGINS, collapsingMargins);
    return this;
  }
}
