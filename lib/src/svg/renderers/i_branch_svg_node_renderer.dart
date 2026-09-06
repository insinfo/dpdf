import 'package:dpdf/src/svg/renderers/i_svg_node_renderer.dart';

/// Interface that defines branches in the NodeRenderer structure.
/// Differs from a leaf renderer in that a branch has children and as such
/// methods that can add or retrieve those children.
abstract class IBranchSvgNodeRenderer implements ISvgNodeRenderer {
  /// Adds a renderer as the last element of the list of children.
  void addChild(ISvgNodeRenderer child);

  /// Gets all child renderers of this object.
  List<ISvgNodeRenderer> getChildren();
}
