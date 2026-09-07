import 'package:dpdf/src/layout/property_container.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';

abstract class CraftElement implements CraftPropertyContainer {
  void setNextRenderer(CraftRenderer renderer);

  CraftRenderer? getRenderer();

  CraftRenderer? createRendererSubTree();
}
