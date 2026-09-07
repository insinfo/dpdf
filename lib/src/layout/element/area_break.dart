import 'package:dpdf/src/layout/element/abstract_element.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/renderer/area_break_renderer.dart';

class AreaBreak extends AbstractElement {
  AreaBreak() {
    // defaults
  }

  @override
  Renderer makeNewRenderer() {
    return AreaBreakRenderer(this);
  }
}
