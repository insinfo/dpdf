import 'package:itext/src/layout/element_property_container.dart';
import 'package:itext/src/layout/element/i_element.dart';
import 'package:itext/src/layout/element/i_abstract_element.dart';
import 'package:itext/src/layout/renderer/i_renderer.dart';

abstract class AbstractElement<T extends IElement>
    extends ElementPropertyContainer<T> implements IAbstractElement {
  IRenderer? nextRenderer;
  final List<IElement> childElements = [];

  @override
  List<IElement> getChildren() => childElements;

  @override
  void setNextRenderer(IRenderer renderer) {
    nextRenderer = renderer;
  }

  @override
  IRenderer? getRenderer() {
    if (nextRenderer != null) {
      return nextRenderer;
    }
    return makeNewRenderer();
  }

  @override
  IRenderer? createRendererSubTree() {
    IRenderer? renderer = getRenderer();
    for (var child in childElements) {
      renderer?.addChild(child.createRendererSubTree()!);
    }
    return renderer;
  }

  IRenderer makeNewRenderer();
}
