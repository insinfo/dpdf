import 'package:dpdf/src/styledxmlparser/node/i_node.dart';
import 'package:dpdf/src/styledxmlparser/css/media/media_device_description.dart';

class CssStyleSheet {
  void appendCssStyleSheet(CssStyleSheet other) {}

  List<CssDeclaration> getCssDeclarations(
      INode node, MediaDeviceDescription deviceDescription) {
    return [];
  }

  static Map<String, String> extractStylesFromRuleSets(
      List<CssRuleSet> ruleSets) {
    return {};
  }

  Iterable<CssStatement> getStatements() => [];
}

abstract class CssStatement {}

class CssDeclaration extends CssStatement {
  String getProperty() => "";
  String getExpression() => "";
}

class CssFontFaceRule extends CssStatement {}

class CssMediaRule extends CssStatement {
  bool matchMediaDevice(MediaDeviceDescription deviceDescription) => true;
  Iterable<CssStatement> getStatements() => [];
}

class CssRuleSet {
  CssRuleSet(dynamic selector, List<CssDeclaration> declarations);
}
