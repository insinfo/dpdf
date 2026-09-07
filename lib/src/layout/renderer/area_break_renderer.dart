import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/element/element.dart';
import 'package:dpdf/src/layout/element/area_break.dart';
import 'package:dpdf/src/commons/dpdf_log_manager.dart';
import 'package:dpdf/src/layout/logs/layout_log_message_constant.dart';

import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';

class AreaBreakRenderer extends AbstractRenderer {
  static final _logger = LogManager.getLoggerByName('AreaBreakRenderer');
  AreaBreak areaBreak;

  AreaBreakRenderer(this.areaBreak) : super(areaBreak);

  @override
  void addChild(Renderer renderer) {
    _logger.logWarning(LayoutLogMessageConstant.areaBreakUnexpected);
  }

  @override
  void setParent(Renderer? parent) {
    // Do nothing or store if needed
  }

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    return LayoutResult(LayoutResult.NOTHING, null, null, null, this)
        .setAreaBreak(areaBreak);
  }

  @override
  Future<void> draw(DrawContext drawContext) async {
    _logger.logWarning(LayoutLogMessageConstant.areaBreakUnexpected);
  }

  @override
  Element? getModelElement() {
    return null;
  }

  @override
  Renderer? getNextRenderer() {
    return null;
  }

  @override
  MinMaxWidth? getMinMaxWidth() {
    return MinMaxWidth(0);
  }
}
