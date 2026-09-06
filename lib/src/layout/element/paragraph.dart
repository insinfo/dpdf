import 'package:pdfcraft/src/layout/element/block_element.dart';
import 'package:pdfcraft/src/layout/element/element.dart';
import 'package:pdfcraft/src/layout/element/text.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';
import 'package:pdfcraft/src/layout/renderer/paragraph_renderer.dart';
import 'package:pdfcraft/src/kernel/pdf/tagutils/accessibility_properties.dart';

class CraftParagraph extends CraftBlockElement<CraftParagraph> {
  CraftParagraph([String? text]) {
    if (text != null) {
      addText(text);
    }
  }

  CraftParagraph add(CraftElement element) {
    childElements.add(element);
    return this;
  }

  CraftParagraph addText(String text) {
    childElements.add(CraftText(text));
    return this;
  }

  @override
  CraftRenderer makeNewRenderer() {
    return CraftParagraphRenderer(this);
  }

  @override
  CraftAccessibilityProperties getAccessibilityProperties() {
    return CraftAccessibilityProperties(); // Stub
  }
}
