import 'package:dpdf/src/kernel/geom/matrix.dart';
import 'package:dpdf/src/kernel/pdf/canvas/canvas_graphics_state.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

import 'event_data.dart';

/// Info for text rendering event.
class CraftTextRenderInfo implements CraftEventData {
  final CraftPdfString text;
  final CraftCanvasGraphicsState graphicsState;
  final CraftMatrix textMatrix;

  CraftTextRenderInfo(this.text, this.graphicsState, this.textMatrix);

  String getText() => text.getValue();
}
