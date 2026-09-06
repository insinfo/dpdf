import 'package:pdfcraft/src/kernel/geom/rectangle.dart';
import 'package:pdfcraft/src/svg/renderers/svg_draw_context.dart';

/// Contract for rendering an SVG node onto a PDF canvas.
/// passed in SvgDrawContext, applying styling (CSS and attributes).
abstract class CraftSvgNodeRenderer {
  /// Sets the parent of this renderer.
  void setParent(CraftSvgNodeRenderer? parent);

  /// Gets the parent of this renderer.
  CraftSvgNodeRenderer? getParent();

  /// Renders this node using the drawing context.
  Future<void> draw(CraftSvgDrawContext context);

  /// Sets the map of XML node attributes and CSS style properties.
  void setAttributesAndStyles(Map<String, String> attributesAndStyles);

  /// Retrieves the property value for a given key name.
  String? getAttribute(String key);

  /// Sets a property key and value pairs for a given attribute.
  void setAttribute(String key, String value);

  /// Get a modifiable copy of the style and attribute map.
  Map<String, String> getAttributeMapCopy();

  /// Creates a deep copy of this renderer.
  CraftSvgNodeRenderer createDeepCopy();

  /// Calculates the current object bounding box.
  CraftRectangle? getObjectBoundingBox(CraftSvgDrawContext context);
}
