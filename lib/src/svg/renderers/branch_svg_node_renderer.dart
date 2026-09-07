import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';

/// Interface that defines branches in the NodeRenderer structure.
/// Differs from a leaf renderer in that a branch has children and as such
/// methods that can add or retrieve those children.
abstract class BranchSvgNodeRenderer implements SvgNodeRenderer {
  /// Appends a child renderer.
  void addChild(SvgNodeRenderer child);

  /// Gets all child renderers of this object.
  List<SvgNodeRenderer> getChildren();
}
