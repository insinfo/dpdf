import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/element/i_element.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/i_property_container.dart';

abstract class IRenderer implements IPropertyContainer {
  void addChild(IRenderer renderer);

  List<IRenderer> getChildRenderers();

  IElement? getModelElement();

  LayoutArea? getOccupiedArea();

  IRenderer? getNextRenderer();

  LayoutResult? layout(LayoutContext layoutContext);

  Future<void> draw(DrawContext drawContext);

  void setParent(IRenderer? parent);

  MinMaxWidth? getMinMaxWidth();

  void move(double dx, double dy);
}
