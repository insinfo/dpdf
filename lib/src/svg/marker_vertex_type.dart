import 'svg_constants.dart';

/// Defines a property of markable elements (<path>, <line>, <polyline> or
/// <polygon>) which is used to determine at which vertices a marker should be drawn.
class MarkerVertexType {
  /// Specifies that marker will be drawn only at the first vertex of element.
  static final MarkerVertexType MARKER_START =
      MarkerVertexType._(SvgConstants.Attributes.MARKER_START);

  /// Specifies that marker will be drawn at every vertex except the first and last.
  static final MarkerVertexType MARKER_MID =
      MarkerVertexType._(SvgConstants.Attributes.MARKER_MID);

  /// Specifies that marker will be drawn only at the last vertex of element.
  static final MarkerVertexType MARKER_END =
      MarkerVertexType._(SvgConstants.Attributes.MARKER_END);

  final String _name;

  MarkerVertexType._(this._name);

  @override
  String toString() {
    return _name;
  }
}
