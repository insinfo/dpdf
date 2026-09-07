import 'package:pdfcraft/src/kernel/geom/matrix.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_literal.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_object.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_string.dart';

import 'data/text_render_info.dart';
import 'event_type.dart';
import 'content_operator.dart';
import 'pdf_canvas_processor.dart';

/// 'BT' operator.
class BeginText implements CraftContentOperator {
  @override
  void invoke(CraftPdfCanvasProcessor processor, CraftPdfLiteral operator,
      List<CraftPdfObject> operands) {
    processor.setTextMatrix(CraftMatrix());
    processor.setTextLineMatrix(CraftMatrix());
    processor
        .getEventListener()
        .eventOccurred(null, CraftEventType.beginTextBlock);
  }
}

/// 'ET' operator.
class EndText implements CraftContentOperator {
  @override
  void invoke(CraftPdfCanvasProcessor processor, CraftPdfLiteral operator,
      List<CraftPdfObject> operands) {
    processor.setTextMatrix(CraftMatrix());
    processor.setTextLineMatrix(CraftMatrix());
    processor
        .getEventListener()
        .eventOccurred(null, CraftEventType.endTextBlock);
  }
}

/// 'Tj' operator.
class ShowText implements CraftContentOperator {
  @override
  void invoke(CraftPdfCanvasProcessor processor, CraftPdfLiteral operator,
      List<CraftPdfObject> operands) {
    if (operands.isNotEmpty && operands[0] is CraftPdfString) {
      final text = operands[0] as CraftPdfString;
      final info = CraftTextRenderInfo(
          text, processor.getGraphicsState(), processor.getTextMatrix());
      processor
          .getEventListener()
          .eventOccurred(info, CraftEventType.renderText);
    }
  }
}

/// 'q' operator.
class SaveState implements CraftContentOperator {
  @override
  void invoke(CraftPdfCanvasProcessor processor, CraftPdfLiteral operator,
      List<CraftPdfObject> operands) {
    processor.saveGraphicsState();
  }
}

/// 'Q' operator.
class RestoreState implements CraftContentOperator {
  @override
  void invoke(CraftPdfCanvasProcessor processor, CraftPdfLiteral operator,
      List<CraftPdfObject> operands) {
    processor.restoreGraphicsState();
  }
}
