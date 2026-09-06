import 'package:dpdf/src/styledxmlparser/css/resolve/abstract_css_context.dart';
import 'package:dpdf/src/styledxmlparser/node/i_node.dart';

/// Interface for CSS resolvers.
abstract class ICssResolver {
  /// Resolves the styles of a node given the passed context.
  ///
  /// [node] the node
  /// [context] the CSS context (RootFontSize, etc.)
  /// returns the map containing the resolved styles
  Map<String, String> resolveStyles(INode node, AbstractCssContext context);
}
