import 'package:itext/src/layout/element/i_element.dart';
import 'package:itext/src/layout/renderer/i_renderer.dart';

abstract class AbstractRenderer implements IRenderer {
  final IElement? modelElement;

  AbstractRenderer(this.modelElement);

  @override
  IElement? getModelElement() {
    return modelElement;
  }

  @override
  void addChild(IRenderer renderer) {
    // Default no-op or throw?
    // BlockRenderer should implement it.
  }

  @override
  IRenderer? getNextRenderer() {
    return null;
  }
}
