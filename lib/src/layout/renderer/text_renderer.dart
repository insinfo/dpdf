import 'package:itext/src/layout/element/text.dart';
import 'package:itext/src/layout/renderer/abstract_renderer.dart';

class TextRenderer extends AbstractRenderer {
  String text;

  TextRenderer(Text textElement, this.text) : super(textElement);

  @override
  Text getModelElement() {
    return super.getModelElement() as Text;
  }
}
