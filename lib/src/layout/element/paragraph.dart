import 'package:dpdf/src/layout/element/block_element.dart';
import 'package:dpdf/src/layout/element/element.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/renderer/paragraph_renderer.dart';
import 'package:dpdf/src/kernel/pdf/tagutils/accessibility_properties.dart';

class Paragraph extends BlockElement<Paragraph> {
  Paragraph([String? text]) {
    if (text != null) {
      addText(text);
    }
  }

  @override
  Paragraph add(Element element) {
    childElements.add(element);
    return this;
  }

  Paragraph addText(String text) {
    childElements.add(Text(text));
    return this;
  }

  @override
  Renderer makeNewRenderer() {
    return ParagraphRenderer(this);
  }

  @override
  AccessibilityProperties getAccessibilityProperties() {
    return AccessibilityProperties(); // Stub
  }
}
