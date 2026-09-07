import 'dart:async';

import '../../pdf_literal.dart';
import '../../pdf_object.dart';
import 'pdf_canvas_processor.dart';

/// Interface for content stream operators.
abstract class ContentOperator {
  /// Invokes the operator, awaiting only implementations that return a Future.
  FutureOr<void> invoke(PdfCanvasProcessor processor, PdfLiteral operator,
      List<PdfObject> operands);
}
