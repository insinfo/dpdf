import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/element/i_element.dart';
import 'package:dpdf/src/layout/element/area_break.dart';
import 'package:dpdf/src/layout/logs/layout_log_message_constant.dart';

import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';

class AreaBreakRenderer extends AbstractRenderer {
  AreaBreak areaBreak;

  AreaBreakRenderer(this.areaBreak) : super(areaBreak);

  @override
  void addChild(IRenderer renderer) {
    // Unsupported
    print(LayoutLogMessageConstant.areaBreakUnexpected);
  }

  @override
  void setParent(IRenderer? parent) {
    // Do nothing or store if needed
  }

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    return LayoutResult(LayoutResult.NOTHING, null, null, null, this)
        .setAreaBreak(areaBreak);
  }

  @override
  Future<void> draw(DrawContext drawContext) async {
    print(LayoutLogMessageConstant.areaBreakUnexpected);
  }

  @override
  IElement? getModelElement() {
    return null;
  }

  @override
  IRenderer? getNextRenderer() {
    return null;
  }

  @override
  MinMaxWidth? getMinMaxWidth() {
    return MinMaxWidth(0);
  }
}
