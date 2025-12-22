import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/element/i_element.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

abstract class IRenderer {
  Future<void> addChild(IRenderer renderer);

  IElement? getModelElement();

  IRenderer? getNextRenderer();

  LayoutResult? layout(LayoutContext layoutContext);

  Future<void> draw(DrawContext drawContext);

  void setParent(IRenderer parent);

  MinMaxWidth? getMinMaxWidth();
}
