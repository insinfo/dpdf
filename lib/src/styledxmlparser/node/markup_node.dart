import 'package:dpdf/src/styledxmlparser/node/attribute.dart';

abstract class MarkupNode {
  MarkupNode? get parentNode;
  List<MarkupNode> get childNodes;
}

abstract class ElementNode extends MarkupNode {
  String get name;
  Iterable<Attribute> getAttributes();
  String? getAttribute(String key);
}

abstract class DataNode extends MarkupNode {
  String getWholeData();
}

abstract class Node extends MarkupNode {
  String wholeText();
}

abstract class XmlDeclarationNode extends MarkupNode {
  String get name;
}
