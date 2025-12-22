import 'package:dpdf/src/layout/element/abstract_element.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/renderer/area_break_renderer.dart';

class AreaBreak extends AbstractElement {
  AreaBreak() {
    // defaults
  }

  @override
  IRenderer makeNewRenderer() {
    return AreaBreakRenderer(this);
  }
}
