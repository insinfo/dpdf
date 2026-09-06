import 'package:pdfcraft/src/layout/element/block_element.dart';
import 'package:pdfcraft/src/layout/element/element.dart';
import 'package:pdfcraft/src/layout/renderer/cell_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';
import 'package:pdfcraft/src/kernel/pdf/tagutils/accessibility_properties.dart';
import 'package:pdfcraft/src/layout/properties/property.dart';

class CraftCell extends CraftBlockElement<CraftCell> {
  int rowspan = 1;
  int colspan = 1;

  CraftCell([int rowspan = 1, int colspan = 1]) {
    this.rowspan = rowspan;
    this.colspan = colspan;
    setProperty(CraftProperty.ROWSPAN, rowspan);
    setProperty(CraftProperty.COLSPAN, colspan);
  }

  CraftCell add(CraftElement element) {
    childElements.add(element);
    return this;
  }

  @override
  CraftRenderer makeNewRenderer() {
    return CraftCellRenderer(this);
  }

  @override
  CraftAccessibilityProperties getAccessibilityProperties() {
    return CraftAccessibilityProperties();
  }
}
