import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';

/// Interface for SvgNodeRenderer, the renderer draws the SVG to its Pdf-canvas
/// passed in SvgDrawContext, applying styling (CSS and attributes).
abstract class ISvgNodeRenderer {
  /// Sets the parent of this renderer.
  void setParent(ISvgNodeRenderer? parent);

  /// Gets the parent of this renderer.
  ISvgNodeRenderer? getParent();

  /// Draws this element to a canvas-like object maintained in the context.
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
  ISvgNodeRenderer createDeepCopy();

  /// Calculates the current object bounding box.
  Rectangle? getObjectBoundingBox(SvgDrawContext context);
}
