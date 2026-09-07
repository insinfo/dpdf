import 'svg_constants.dart';

/// Defines a property of markable elements (<path>, <line>, <polyline> or
/// <polygon>) which is used to determine at which vertices a marker should be drawn.
class MarkerVertexType {
  /// Draws this marker at the initial vertex.
  static final MarkerVertexType MARKER_START =
      MarkerVertexType._(SvgAttributes.MARKER_START);

  /// Draws this marker at internal vertices.
  static final MarkerVertexType MARKER_MID =
      MarkerVertexType._(SvgAttributes.MARKER_MID);

  /// Draws this marker at the final vertex.
  static final MarkerVertexType MARKER_END =
      MarkerVertexType._(SvgAttributes.MARKER_END);

  final String _name;

  MarkerVertexType._(this._name);

  @override
  String toString() {
    return _name;
  }
}
