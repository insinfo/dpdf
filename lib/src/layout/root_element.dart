import 'package:dpdf/src/layout/element_property_container.dart';
import 'package:dpdf/src/layout/properties/leading.dart';
import 'package:dpdf/src/layout/element/block_content.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pending_layout_content.dart';
import 'package:dpdf/src/layout/renderer/root_renderer.dart';
import 'package:dpdf/src/layout/property_container.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/element/div.dart';
import 'package:dpdf/src/layout/properties/text_alignment.dart';
import 'package:dpdf/src/layout/properties/vertical_alignment.dart';
import 'package:dpdf/src/layout/properties/horizontal_alignment.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/kernel/pdf/tagging/standard_roles.dart';

/// Root of a layout tree: the object content is added to before it is placed
/// on a page.
///
/// [add] is synchronous and only queues. Everything that needs the document —
/// creating pages, measuring text, drawing — happens in [close], which must be
/// awaited. An element added after [close] is rejected.
abstract class RootElement<T extends PropertyContainer>
    extends ElementPropertyContainer<T> implements PendingLayoutContent {
  PdfDocument pdfDocument;
  RootRenderer? rootRenderer;
  bool immediateFlush = true;

  /// Elements accepted by [add] and not laid out yet, in the order they came.
  final List<BlockContent> _queued = [];
  bool _closed = false;

  RootElement(this.pdfDocument) {
    pdfDocument.registerPendingLayoutContent(this);
  }

  /// Appends [element] to the content of this root.
  ///
  /// This only records the element: no page is created and nothing is measured
  /// or drawn until [close] runs. The queue keeps insertion order, so an
  /// `AreaBreak` placed between two paragraphs still breaks between them.
  ///
  /// Because the work is deferred, an element must not be mutated after it is
  /// added: [close] lays out the object as it stands then, not as it stood
  /// here.
  T add(BlockContent element) {
    if (_closed) {
      throw StateError(
          'This ${pendingContentOwner()} is closed; add() no longer accepts '
          'content.');
    }
    _queued.add(element);
    return this as T;
  }

  @override
  int pendingContentCount() =>
      _queued.length + (rootRenderer?.getChildRenderers().length ?? 0);

  @override
  String pendingContentOwner() => runtimeType.toString();

  /// Lays out and draws everything [add] has queued, in order.
  ///
  /// A layout failure aborts the remaining queue and reaches the caller of
  /// [close]; nothing is retained, so the failure is reported once.
  Future<void> layoutQueuedContent() async {
    try {
      while (_queued.isNotEmpty) {
        final element = _queued.removeAt(0);
        final renderer = element.createRendererSubTree();
        if (renderer == null) continue;
        await ensureRootRendererNotNull().addChild(renderer);
      }
    } on Object {
      _queued.clear();
      rethrow;
    }
  }

  RootRenderer ensureRootRendererNotNull();

  /// Draws [text] as a standalone paragraph anchored at ([x], [y]).
  ///
  /// Like [add], this only queues: the placement happens in [close].
  T showTextAligned(
      {required String text,
      required double x,
      required double y,
      required TextAlignment textAlign,
      VerticalAlignment? vertAlign,
      double angle = 0,
      int pageNumber = 0}) {
    Paragraph p = Paragraph();
    p.add(Text(text));
    p.setMargin(0);
    p.setProperty(Property.LEADING, Leading(Leading.MULTIPLIED, 1.0));

    return showTextAlignedParagraph(
        p: p,
        x: x,
        y: y,
        textAlign: textAlign,
        vertAlign: vertAlign,
        angle: angle,
        pageNumber: pageNumber);
  }

  /// Anchors an existing paragraph at ([x], [y]). Queues, like [add].
  T showTextAlignedParagraph(
      {required Paragraph p,
      required double x,
      required double y,
      required TextAlignment textAlign,
      VerticalAlignment? vertAlign,
      double angle = 0,
      int pageNumber = 0}) {
    if (pageNumber == 0) pageNumber = 1;

    Div div = Div();
    div.setTextAlignment(textAlign);
    if (vertAlign != null) {
      div.setVerticalAlignment(vertAlign);
    }
    if (angle != 0) {
      div.setRotationAngle(angle);
    }
    div.setProperty(Property.ROTATION_POINT_X, x);
    div.setProperty(Property.ROTATION_POINT_Y, y);

    double divSize = 5000;
    double divX = x;
    double divY = y;

    if (textAlign == TextAlignment.center) {
      divX = x - divSize / 2;
      p.setHorizontalAlignment(HorizontalAlignment.center);
    } else if (textAlign == TextAlignment.right) {
      divX = x - divSize;
      p.setHorizontalAlignment(HorizontalAlignment.right);
    }

    if (vertAlign == VerticalAlignment.middle) {
      divY = y - divSize / 2;
    } else if (vertAlign == VerticalAlignment.top) {
      // Check enum case
      divY = y - divSize;
    }

    div.setFixedPosition(pageNumber, divX, divY, divSize);
    div.setMinHeight(divSize);

    // The wrapper div only carries the placement: when the paragraph itself
    // is not tagged, the wrapper is marked as an artifact so it does not add a
    // spurious level to the structure tree (ISO 32000-1, 14.8.2.2).
    if (p.getAccessibilityProperties().getRole() == null) {
      div.getAccessibilityProperties().setRole(StandardRoles.artifact);
    }

    div.add(p);
    return add(div);
  }

  /// Whether [close] has already run on this root.
  bool isClosed() => _closed;

  /// Lays out the queued content and releases the renderer.
  ///
  /// This is where every error a layout can raise surfaces, including errors
  /// caused by an element that [add] merely accepted.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    pdfDocument.unregisterPendingLayoutContent(this);
    try {
      await layoutQueuedContent();
    } on Object {
      // What did get laid out is still written out, but the layout error is
      // what the caller hears about.
      try {
        await closeRootRenderer();
      } on Object {
        // Reported through the original error.
      }
      rethrow;
    }
    await closeRootRenderer();
  }

  /// Flushes and closes the renderer this root built, if it built one.
  Future<void> closeRootRenderer();
}
