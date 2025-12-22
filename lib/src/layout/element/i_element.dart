import 'package:itext/src/layout/i_property_container.dart';
import 'package:itext/src/layout/renderer/i_renderer.dart';

abstract class IElement implements IPropertyContainer {
  void setNextRenderer(IRenderer renderer);

  IRenderer? getRenderer();

  IRenderer? createRendererSubTree();
}
