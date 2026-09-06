import 'package:pdfcraft/src/layout/renderer/abstract_renderer.dart';
import 'package:pdfcraft/src/layout/layout/layout_area.dart';
import 'package:pdfcraft/src/layout/layout/layout_result.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';

abstract class CraftRootRenderer extends CraftAbstractRenderer {
  bool immediateFlush = true;
  CraftLayoutArea? currentArea; // Moved from DocumentRenderer
  // waitingDrawingElements should be a Set or List of IRenderer
  final List<CraftRenderer> waitingDrawingElements = [];

  CraftRootRenderer(super.modelElement) {
    // defaults
  }

  Future<void> flushSingleRenderer(CraftRenderer resultRenderer);

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

  Future<CraftLayoutArea?> updateCurrentArea(
      CraftLayoutResult? overflowResult) async {
    return null;
  }

  Future<void> close() async {
    await flush();
  }

  @override
  Future<void> addChild(CraftRenderer renderer) async {
    childRenderers.add(renderer);
    renderer.setParent(this);
  }
}
