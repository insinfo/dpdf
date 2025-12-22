import 'package:dpdf/src/layout/i_property_container.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';

abstract class IElement implements IPropertyContainer {
  void setNextRenderer(IRenderer renderer);

  IRenderer? getRenderer();

  IRenderer? createRendererSubTree();
}
