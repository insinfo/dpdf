import 'package:pdfcraft/src/layout/element/abstract_element.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';
import 'package:pdfcraft/src/layout/renderer/area_break_renderer.dart';

class CraftAreaBreak extends CraftAbstractElement {
  CraftAreaBreak() {
    // defaults
  }

  @override
  CraftRenderer makeNewRenderer() {
    return CraftAreaBreakRenderer(this);
  }
}
