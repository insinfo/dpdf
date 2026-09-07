import 'package:dpdf/src/layout/element_property_container.dart';
import 'package:dpdf/src/layout/element/element.dart';
import 'package:dpdf/src/layout/element/element_model.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';

abstract class CraftAbstractElement<T extends CraftElement>
    extends CraftElementPropertyContainer<T> implements CraftElementModel {
  CraftRenderer? nextRenderer;
  final List<CraftElement> childElements = [];

  @override
  List<CraftElement> getChildren() => childElements;

  T add(CraftElement element) {
    childElements.add(element);
    return this as T;
  }

  @override
  void setNextRenderer(CraftRenderer renderer) {
    nextRenderer = renderer;
  }

  @override
  CraftRenderer? getRenderer() {
    if (nextRenderer != null) {
      return nextRenderer;
    }
    return makeNewRenderer();
  }

  @override
  CraftRenderer? createRendererSubTree() {
    CraftRenderer? renderer = getRenderer();
    for (var child in childElements) {
      renderer?.addChild(child.createRendererSubTree()!);
    }
    return renderer;
  }

  CraftRenderer makeNewRenderer();
}
