import 'package:dpdf/src/layout/property_container.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';

abstract class Element implements PropertyContainer {
  void setNextRenderer(Renderer renderer);

  Renderer? getRenderer();

  Renderer? createRendererSubTree();
}
