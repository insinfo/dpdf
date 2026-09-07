import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';

/// Exception thrown by ISvgProcessor when it cannot process an SVG
class CraftSvgProcessingException extends CraftPdfException {
  /// Creates a new SvgProcessingException instance.
  CraftSvgProcessingException(super.message, {dynamic super.cause});
}
