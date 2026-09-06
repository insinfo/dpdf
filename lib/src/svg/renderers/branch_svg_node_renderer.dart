import 'package:pdfcraft/src/svg/renderers/svg_node_renderer.dart';

/// Interface that defines branches in the NodeRenderer structure.
/// Differs from a leaf renderer in that a branch has children and as such
/// methods that can add or retrieve those children.
abstract class CraftBranchSvgNodeRenderer implements CraftSvgNodeRenderer {
  /// Appends a child renderer.
  void addChild(CraftSvgNodeRenderer child);

  /// Gets all child renderers of this object.
  List<CraftSvgNodeRenderer> getChildren();
}
