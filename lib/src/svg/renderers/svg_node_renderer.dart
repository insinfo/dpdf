import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';

/// Contract for rendering an SVG node onto a PDF canvas.
/// passed in SvgDrawContext, applying styling (CSS and attributes).
abstract class SvgNodeRenderer {
  /// Sets the parent of this renderer.
  void setParent(SvgNodeRenderer? parent);

  /// Gets the parent of this renderer.
  SvgNodeRenderer? getParent();

  /// Renders this node using the drawing context.
  Future<void> draw(SvgDrawContext context);

  /// Sets the map of XML node attributes and CSS style properties.
  void setAttributesAndStyles(Map<String, String> attributesAndStyles);

  /// Retrieves the property value for a given key name.
  String? getAttribute(String key);

  /// Sets a property key and value pairs for a given attribute.
  void setAttribute(String key, String value);

  /// Get a modifiable copy of the style and attribute map.
  Map<String, String> getAttributeMapCopy();

  /// Creates a deep copy of this renderer.
  SvgNodeRenderer createDeepCopy();

  /// Calculates the current object bounding box.
  Rectangle? getObjectBoundingBox(SvgDrawContext context);
}
