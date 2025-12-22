import 'package:itext/src/layout/element/block_element.dart';
import 'package:itext/src/layout/element/i_element.dart';
import 'package:itext/src/layout/element/text.dart';
import 'package:itext/src/layout/renderer/i_renderer.dart';
import 'package:itext/src/layout/renderer/paragraph_renderer.dart';
import 'package:itext/src/kernel/pdf/tagutils/accessibility_properties.dart';

class Paragraph extends BlockElement<Paragraph> {
  Paragraph([String? text]) {
    if (text != null) {
      addText(text);
    }
  }

  Paragraph add(IElement element) {
    childElements.add(element);
    return this;
  }

  Paragraph addText(String text) {
    childElements.add(Text(text));
    return this;
  }

  @override
  IRenderer makeNewRenderer() {
    return ParagraphRenderer(this);
  }

  @override
  AccessibilityProperties getAccessibilityProperties() {
    return AccessibilityProperties(); // Stub
  }
}
