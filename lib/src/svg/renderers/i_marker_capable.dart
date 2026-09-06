import 'package:dpdf/src/svg/marker_vertex_type.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';

/// Interface implemented by elements that support marker drawing.
abstract class IMarkerCapable {
  /// Draws a marker in the specified context.
  void drawMarker(SvgDrawContext context, MarkerVertexType markerVertexType);

  /// Calculates marker orientation angle if orient attribute is set to auto
  double getAutoOrientAngle(dynamic marker,
      bool reverse); // Using dynamic for MarkerSvgNodeRenderer for now
}
