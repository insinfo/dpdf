import 'package:dpdf/src/kernel/geom/matrix.dart';
import 'package:dpdf/src/kernel/pdf/pdf_literal.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

import 'data/text_render_info.dart';
import 'event_type.dart';
import 'content_operator.dart';
import 'pdf_canvas_processor.dart';

/// 'BT' operator.
class BeginText implements ContentOperator {
  @override
  void invoke(PdfCanvasProcessor processor, PdfLiteral operator,
      List<PdfObject> operands) {
    processor.setTextMatrix(Matrix());
    processor.setTextLineMatrix(Matrix());
    processor.getEventListener().eventOccurred(null, EventType.beginTextBlock);
  }
}

/// 'ET' operator.
class EndText implements ContentOperator {
  @override
  void invoke(PdfCanvasProcessor processor, PdfLiteral operator,
      List<PdfObject> operands) {
    processor.setTextMatrix(Matrix());
    processor.setTextLineMatrix(Matrix());
    processor.getEventListener().eventOccurred(null, EventType.endTextBlock);
  }
}

/// 'Tj' operator.
class ShowText implements ContentOperator {
  @override
  void invoke(PdfCanvasProcessor processor, PdfLiteral operator,
      List<PdfObject> operands) {
    if (operands.isNotEmpty && operands[0] is PdfString) {
      final text = operands[0] as PdfString;
      final info = TextRenderInfo(
          text, processor.getGraphicsState(), processor.getTextMatrix());
      processor.getEventListener().eventOccurred(info, EventType.renderText);
    }
  }
}

/// 'q' operator.
class SaveState implements ContentOperator {
  @override
  void invoke(PdfCanvasProcessor processor, PdfLiteral operator,
      List<PdfObject> operands) {
    processor.saveGraphicsState();
  }
}

/// 'Q' operator.
class RestoreState implements ContentOperator {
  @override
  void invoke(PdfCanvasProcessor processor, PdfLiteral operator,
      List<PdfObject> operands) {
    processor.restoreGraphicsState();
  }
}
