import 'package:dpdf/src/styledxmlparser/node/i_attribute.dart';

abstract class INode {
  INode? get parentNode;
  List<INode> get childNodes;
}

abstract class IElementNode extends INode {
  String get name;
  Iterable<IAttribute> getAttributes();
  String? getAttribute(String key);
}

abstract class IDataNode extends INode {
  String getWholeData();
}

abstract class Node extends INode {
  String wholeText();
}

abstract class IXmlDeclarationNode extends INode {
  String get name;
}
