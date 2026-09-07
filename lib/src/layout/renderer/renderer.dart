import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';

import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/property_container.dart';

abstract class CraftRenderer implements CraftPropertyContainer {
  void addChild(CraftRenderer renderer);

  List<CraftRenderer> getChildRenderers();

  CraftPropertyContainer? getModelElement();

  CraftLayoutArea? getOccupiedArea();

  CraftRenderer? getNextRenderer();

  CraftLayoutResult? layout(CraftLayoutContext layoutContext);

  Future<void> draw(CraftDrawContext drawContext);

  void setParent(CraftRenderer? parent);

  CraftMinMaxWidth? getMinMaxWidth();

  void move(double dx, double dy);
}
