import 'package:pdfcraft/src/kernel/exceptions/pdf_exception.dart';

/// Exception thrown by ISvgProcessor when it cannot process an SVG
class CraftSvgProcessingException extends CraftPdfException {
  /// Creates a new SvgProcessingException instance.
  CraftSvgProcessingException(String message, {dynamic cause})
      : super(message, cause: cause);
}
