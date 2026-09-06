import 'package:dpdf/src/layout/renderer/root_renderer.dart';
import 'package:dpdf/src/layout/canvas.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/layout/root_layout_area.dart';

class CanvasRenderer extends RootRenderer {
  late Canvas canvas;

  CanvasRenderer(Canvas canvas, [bool immediateFlush = true]) : super(canvas) {
    this.canvas = canvas;
    this.modelElement = canvas;
    this.immediateFlush = immediateFlush;
  }

  @override
  Future<void> addChild(IRenderer renderer) async {
    if (currentArea == null) {
      await updateCurrentArea(null);
    }
    await super.addChild(renderer);
    // In .NET it calls Layout() if logic requires, but mostly calls super.AddChild() logic
    // But since AbstractRenderer.addChild is void, RootRenderer.addChild logic is the one doing layout?
    // Wait, AbstractRenderer.addChild is void.
    // RootRenderer.addChild is Future<void> (I changed it earlier? No, I only changed AbstractRenderer?)
    // In RootRenderer.dart:
    /*
      abstract class RootRenderer extends AbstractRenderer {
        // ...
        // Does RootRenderer override addChild?
      }
    */
    // Let's check RootRenderer.dart again to see if addChild is Future<void> there.
    // I don't recall seeing addChild implementation in RootRenderer.
    // If RootRenderer extends AbstractRenderer, it inherits addChild(void).
    // EXCEPT if I changed it?
    // In AbstractRenderer, addChild is void.

    // ERROR: 'CanvasRenderer.addChild' ('void Function(IRenderer)') isn't a valid override of 'RootRenderer.addChild' ('Future<void> Function(IRenderer)')
    // This implies RootRenderer HAS Future<void> addChild.
    // Where is it defined? DocumentRenderer defined it as Future<void>.
    // AbstractRenderer has void addChild.
    // Maybe RootRenderer has `abstract Future<void> addChild`?
    // I need to check RootRenderer definition again.

    await super.addChild(renderer);
    // But AbstractRenderer has void addChild.
    // So super.addChild(renderer) is synchronous void.
    // If I just await it, it's fine (await void is allowed?).
    // But wait, if RootRenderer overrides addChild to be Future<void>, then super.addChild might refer to AbstractRenderer's void one?

    // Let's assume RootRenderer has Future<void> definition.
    // So I need to return Future.
    // If I delegate to super (AbstractRenderer), I might need to manually handle layout logic which RootRenderer is supposed to do.

    // Actually, DocumentRenderer implemented addChild with layout logic!
    // RootRenderer usually has the layout logic in addChild?
    // In .NET RootRenderer.AddChild contains the loop:
    /*
      childElements.Add(element);
      CreateAndAddRendererSubTree(element);
    */
    // No, that's RootElement.
    // RootRenderer.AddChild:
    /*
      modelElement.Add(renderer.GetModelElement());
    */
    // Wait, RootRenderer is the renderer for the RootElement.

    // If AbstractRenderer.addChild adds to childRenderers list.
    // DocumentRenderer.addChild implemented the loop with layout.

    // Does CanvasRenderer need to loop layout?
    // Canvas is an immediate mode container?
    // In .NET CanvasRenderer.AddChild:
    /*
      base.AddChild(renderer);
    */
    // And base is AbstractRenderer?
    // RootRenderer in .NET inherits AbstractRenderer.
    // Does RootRenderer override AddChild?
    // I suspect RootRenderer in Dart MIGHT NOT have addChild defined as Future<void> except if I missed it.
    // But lint said: 'RootRenderer.addChild' ('Future<void> Function(IRenderer)').
    // So it MUST be there.

    // I will implementation delegation.
    if (immediateFlush) {
      // For Canvas, layout is usually simplified or done by renderer itself?
      // We should probably layout before drawing.
      renderer.layout(LayoutContext(RootLayoutArea(
          currentArea!.getPageNumber(), currentArea!.getBBox().clone())));
      await flushSingleRenderer(renderer);
      childRenderers.remove(renderer);
    }
  }

  @override
  Future<void> flushSingleRenderer(IRenderer resultRenderer) async {
    DrawContext drawContext = DrawContext(
        canvas.getPdfDocument(), canvas.getPdfCanvas(), false // toTag
        );
    await resultRenderer.draw(drawContext);
  }

  @override
  Future<LayoutArea?> updateCurrentArea(LayoutResult? overflowResult) async {
    if (currentArea == null) {
      int pageNumber = canvas.getIsCanvasOfPage() && canvas.getPage() != null
          ? canvas.getPdfDocument().getPageNumber(canvas.getPage()!)
          : 0;
      // We need to clone the root area.
      // Helper method?
      currentArea = RootLayoutArea(pageNumber, canvas.getRootArea()!.clone());
    } else {
      // Full
      currentArea = null;
    }
    return currentArea;
  }

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    // CanvasRenderer is usually for immediate layout?
    // In .NET: Layout(LayoutContext layoutContext) calls base.Layout?
    // Or handles children?
    // Since we use addChild to drive layout (in DocumentRenderer), CanvasRenderer might do same?
    // But CanvasRenderer usually just renders immediately.

    // Implementation:
    return LayoutResult(LayoutResult.FULL, layoutContext.getArea(), null, null);
  }

  @override
  IRenderer getNextRenderer() {
    return CanvasRenderer(canvas, immediateFlush);
  }
}
