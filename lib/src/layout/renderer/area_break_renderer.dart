import 'package:pdfcraft/src/layout/renderer/renderer.dart';
import 'package:pdfcraft/src/layout/layout/layout_context.dart';
import 'package:pdfcraft/src/layout/layout/layout_result.dart';
import 'package:pdfcraft/src/layout/renderer/draw_context.dart';
import 'package:pdfcraft/src/layout/element/element.dart';
import 'package:pdfcraft/src/layout/element/area_break.dart';
import 'package:pdfcraft/src/commons/pdfcraft_log_manager.dart';
import 'package:pdfcraft/src/layout/logs/layout_log_message_constant.dart';

import 'package:pdfcraft/src/layout/minmaxwidth/min_max_width.dart';

import 'package:pdfcraft/src/layout/renderer/abstract_renderer.dart';

class CraftAreaBreakRenderer extends CraftAbstractRenderer {
  static final _logger = LogManager.getLoggerByName('AreaBreakRenderer');
  CraftAreaBreak areaBreak;

  CraftAreaBreakRenderer(this.areaBreak) : super(areaBreak);

  @override
  void addChild(CraftRenderer renderer) {
    _logger.logWarning(CraftLayoutLogMessageConstant.areaBreakUnexpected);
  }

  @override
  void setParent(CraftRenderer? parent) {
    // Do nothing or store if needed
  }

  @override
  CraftLayoutResult? layout(CraftLayoutContext layoutContext) {
    return CraftLayoutResult(CraftLayoutResult.NOTHING, null, null, null, this)
        .setAreaBreak(areaBreak);
  }

  @override
  Future<void> draw(CraftDrawContext drawContext) async {
    _logger.logWarning(CraftLayoutLogMessageConstant.areaBreakUnexpected);
  }

  @override
  CraftElement? getModelElement() {
    return null;
  }

  @override
  CraftRenderer? getNextRenderer() {
    return null;
  }

  @override
  CraftMinMaxWidth? getMinMaxWidth() {
    return CraftMinMaxWidth(0);
  }
}
