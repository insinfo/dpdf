import 'package:dpdf/src/layout/element_property_container.dart';
import 'package:dpdf/src/layout/element/element.dart';
import 'package:dpdf/src/layout/element/element_model.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';

abstract class AbstractElement<T extends Element>
    extends ElementPropertyContainer<T> implements ElementModel {
  Renderer? nextRenderer;
  final List<Element> childElements = [];

  @override
  List<Element> getChildren() => childElements;

  T add(Element element) {
    childElements.add(element);
    return this as T;
  }

  @override
  void setNextRenderer(Renderer renderer) {
    nextRenderer = renderer;
  }

  @override
  Renderer? getRenderer() {
    if (nextRenderer != null) {
      return nextRenderer;
    }
    return makeNewRenderer();
  }

  @override
  Renderer? createRendererSubTree() {
    Renderer? renderer = getRenderer();
    for (var child in childElements) {
      renderer?.addChild(child.createRendererSubTree()!);
    }
    return renderer;
  }

  Renderer makeNewRenderer();
}
