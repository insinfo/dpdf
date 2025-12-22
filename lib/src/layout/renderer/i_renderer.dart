import 'package:itext/src/layout/element/i_element.dart';

abstract class IRenderer {
  void addChild(IRenderer renderer);

  IElement? getModelElement();

  IRenderer? getNextRenderer();

  // TODO: Add layout and draw methods
}
