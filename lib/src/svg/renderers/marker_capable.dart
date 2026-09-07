import 'dart:math' as math;

import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';

class SvgMarkerVertex {
  final double x;
  final double y;
  final double incomingAngle;
  final double outgoingAngle;
  final bool isStart;
  final bool isEnd;

  const SvgMarkerVertex(this.x, this.y, this.incomingAngle, this.outgoingAngle,
      {this.isStart = false, this.isEnd = false});

  double get middleAngle {
    final x = math.cos(incomingAngle) + math.cos(outgoingAngle);
    final y = math.sin(incomingAngle) + math.sin(outgoingAngle);
    if (x.abs() < 1e-12 && y.abs() < 1e-12) return outgoingAngle;
    return math.atan2(y, x);
  }
}

abstract class MarkerCapable {
  List<SvgMarkerVertex> markerVertices(SvgDrawContext context);
}
