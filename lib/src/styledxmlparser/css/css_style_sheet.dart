import 'package:dpdf/src/styledxmlparser/node/markup_node.dart';
import 'package:dpdf/src/styledxmlparser/css/media/media_device_description.dart';

class CraftCssStyleSheet {
  void appendCssStyleSheet(CraftCssStyleSheet other) {}

  List<CraftCssDeclaration> getCssDeclarations(
      CraftMarkupNode node, CraftMediaDeviceDescription deviceDescription) {
    return [];
  }

  static Map<String, String> extractStylesFromRuleSets(
      List<CraftCssRuleSet> ruleSets) {
    return {};
  }

  Iterable<CraftCssStatement> getStatements() => [];
}

abstract class CraftCssStatement {}

class CraftCssDeclaration extends CraftCssStatement {
  String getProperty() => "";
  String getExpression() => "";
}

class CraftCssFontFaceRule extends CraftCssStatement {}

class CraftCssMediaRule extends CraftCssStatement {
  bool matchMediaDevice(CraftMediaDeviceDescription deviceDescription) => true;
  Iterable<CraftCssStatement> getStatements() => [];
}

class CraftCssRuleSet {
  CraftCssRuleSet(dynamic selector, List<CraftCssDeclaration> declarations);
}
