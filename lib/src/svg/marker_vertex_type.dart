import 'svg_constants.dart';

/// Defines a property of markable elements (<path>, <line>, <polyline> or
/// <polygon>) which is used to determine at which vertices a marker should be drawn.
class CraftMarkerVertexType {
  /// Draws this marker at the initial vertex.
  static final CraftMarkerVertexType MARKER_START =
      CraftMarkerVertexType._(CraftSvgConstants.Attributes.MARKER_START);

  /// Draws this marker at internal vertices.
  static final CraftMarkerVertexType MARKER_MID =
      CraftMarkerVertexType._(CraftSvgConstants.Attributes.MARKER_MID);

  /// Draws this marker at the final vertex.
  static final CraftMarkerVertexType MARKER_END =
      CraftMarkerVertexType._(CraftSvgConstants.Attributes.MARKER_END);

  final String _name;

  CraftMarkerVertexType._(this._name);

  @override
  String toString() {
    return _name;
  }
}
