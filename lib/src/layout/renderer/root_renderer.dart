import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';

abstract class RootRenderer extends AbstractRenderer {
  RootRenderer() : super(null);

  @override
  Future<void> addChild(IRenderer renderer) async {
    // TODO: Implement layout logic
  }
}
