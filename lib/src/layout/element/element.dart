import 'package:pdfcraft/src/layout/property_container.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';

abstract class CraftElement implements CraftPropertyContainer {
  void setNextRenderer(CraftRenderer renderer);

  CraftRenderer? getRenderer();

  CraftRenderer? createRendererSubTree();
}
