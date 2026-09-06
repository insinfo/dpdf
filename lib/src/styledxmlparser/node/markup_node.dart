import 'package:pdfcraft/src/styledxmlparser/node/attribute.dart';

abstract class CraftMarkupNode {
  CraftMarkupNode? get parentNode;
  List<CraftMarkupNode> get childNodes;
}

abstract class CraftElementNode extends CraftMarkupNode {
  String get name;
  Iterable<CraftAttribute> getAttributes();
  String? getAttribute(String key);
}

abstract class CraftDataNode extends CraftMarkupNode {
  String getWholeData();
}

abstract class CraftNode extends CraftMarkupNode {
  String wholeText();
}

abstract class XmlDeclarationNode extends CraftMarkupNode {
  String get name;
}
