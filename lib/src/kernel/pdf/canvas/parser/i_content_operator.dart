import '../../pdf_literal.dart';
import '../../pdf_object.dart';
import 'pdf_canvas_processor.dart';

/// Interface for content stream operators.
abstract class IContentOperator {
  /// Invokes the operator.
  Future<void> invoke(PdfCanvasProcessor processor, PdfLiteral operator,
      List<PdfObject> operands);
}
