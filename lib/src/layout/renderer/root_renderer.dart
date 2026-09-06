import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';

abstract class RootRenderer extends AbstractRenderer {
  bool immediateFlush = true;
  LayoutArea? currentArea; // Moved from DocumentRenderer
  // waitingDrawingElements should be a Set or List of IRenderer
  final List<IRenderer> waitingDrawingElements = [];

  RootRenderer(super.modelElement) {
    // defaults
  }

  Future<void> flushSingleRenderer(IRenderer resultRenderer);

  Future<void> flush() async {
    for (final renderer in waitingDrawingElements) {
      await flushSingleRenderer(renderer);
    }
    waitingDrawingElements.clear();
    for (final renderer in childRenderers) {
      await flushSingleRenderer(renderer);
    }
    childRenderers.clear();
  }

  Future<LayoutArea?> updateCurrentArea(LayoutResult? overflowResult) async {
    return null;
  }

  Future<void> close() async {
    await flush();
  }

  @override
  Future<void> addChild(IRenderer renderer) async {
    childRenderers.add(renderer);
    renderer.setParent(this);
  }
}
