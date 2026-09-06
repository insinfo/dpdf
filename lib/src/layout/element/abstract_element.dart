import 'package:dpdf/src/layout/element_property_container.dart';
import 'package:dpdf/src/layout/element/i_element.dart';
import 'package:dpdf/src/layout/element/i_abstract_element.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';

abstract class AbstractElement<T extends IElement>
    extends ElementPropertyContainer<T> implements IAbstractElement {
  IRenderer? nextRenderer;
  final List<IElement> childElements = [];

  @override
  List<IElement> getChildren() => childElements;

  T add(IElement element) {
    childElements.add(element);
    return this as T;
  }

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
