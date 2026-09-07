import 'package:dpdf/src/svg/renderers/branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_text_util.dart';

/// Utility class which contains methods related to href resolving
class TemplateResolveUtils {
  TemplateResolveUtils._();

  /// Resolve href to other object within svg and fills renderer with its properties and children if needed.
  static void resolve(
      CraftBranchSvgNodeRenderer renderer, CraftSvgDrawContext context) {
    String? href = renderer.getAttribute(CraftSvgConstants.Attributes.HREF);
    href ??= renderer.getAttribute(CraftSvgConstants.Attributes.XLINK_HREF);
    if (href == null || href.isEmpty || href[0] != '#') {
      return;
    }
    String normalizedName = CraftSvgTextUtil.filterReferenceValue(href);
    CraftSvgNodeRenderer? template = context.getNamedObject(normalizedName);
    if (template is! CraftBranchSvgNodeRenderer) {
      return;
    }
    CraftBranchSvgNodeRenderer namedObject =
        template.createDeepCopy() as CraftBranchSvgNodeRenderer;
    resolve(namedObject, context);
    if (renderer.getChildren().isEmpty) {
      for (CraftSvgNodeRenderer child in namedObject.getChildren()) {
        renderer.addChild(child);
      }
    }
    // href attributes inheritance rule are really simple, and only attributes not defined at renderer on which
    // href is resolved should be copied from referenced object
    Map<String, String> referencedAttributes =
        namedObject.getAttributeMapCopy();
    referencedAttributes.forEach((key, value) {
      if (renderer.getAttribute(key) == null) {
        renderer.setAttribute(key, value);
      }
    });
  }
}
