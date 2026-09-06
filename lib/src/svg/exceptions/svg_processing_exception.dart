import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';

/// Exception thrown by ISvgProcessor when it cannot process an SVG
class SvgProcessingException extends PdfException {
  /// Creates a new SvgProcessingException instance.
  SvgProcessingException(String message, {dynamic cause})
      : super(message, cause: cause);
}
