import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';

import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/property_container.dart';

abstract class Renderer implements PropertyContainer {
  void addChild(Renderer renderer);

  List<Renderer> getChildRenderers();

  PropertyContainer? getModelElement();

  LayoutArea? getOccupiedArea();

  Renderer? getNextRenderer();

  LayoutResult? layout(LayoutContext layoutContext);

  Future<void> draw(DrawContext drawContext);

  void setParent(Renderer? parent);

  MinMaxWidth? getMinMaxWidth();

  void move(double dx, double dy);
}
