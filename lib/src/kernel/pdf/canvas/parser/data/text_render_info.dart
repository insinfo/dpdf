import 'package:dpdf/src/kernel/geom/matrix.dart';
import 'package:dpdf/src/kernel/pdf/canvas/canvas_graphics_state.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

import 'i_event_data.dart';

/// Info for text rendering event.
class TextRenderInfo implements IEventData {
  final PdfString text;
  final CanvasGraphicsState graphicsState;
  final Matrix textMatrix;

  TextRenderInfo(this.text, this.graphicsState, this.textMatrix);

  String getText() => text.getValue();
}
