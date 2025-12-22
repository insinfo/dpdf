import 'package:itext/src/layout/renderer/abstract_renderer.dart';
import 'package:itext/src/layout/renderer/i_renderer.dart';

abstract class RootRenderer extends AbstractRenderer {
  RootRenderer() : super(null);

  @override
  void addChild(IRenderer renderer) {
    // TODO: Implement layout logic
  }
}
