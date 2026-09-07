import '../../commons/exceptions/dpdf_exception.dart';

/// Exception thrown when a PDF processing error occurs in the kernel module.
class CraftPdfException extends DpdfException {
  /// Object that was being processed when the exception occurred.
  final Object? pdfObject;

  /// Creates a PdfException with the specified message.
  CraftPdfException(String message, {Object? cause, this.pdfObject})
      : super(message, cause);

  /// Creates a PdfException with message parameters.
  ///
  /// The [message] can contain placeholders like {0}, {1}, etc.
  /// that will be replaced with the provided [params].
  factory CraftPdfException.withParams(String message, List<Object?> params,
      {Object? cause, Object? pdfObject}) {
    var formattedMessage = message;
    for (var i = 0; i < params.length; i++) {
      formattedMessage =
          formattedMessage.replaceAll('{$i}', params[i]?.toString() ?? 'null');
    }
    return CraftPdfException(formattedMessage,
        cause: cause, pdfObject: pdfObject);
  }

  /// Sets the message parameters and returns a new exception.
  ///
  /// Allows fluent API usage:
  /// ```dart
  /// throw PdfException(KernelExceptionMessageConstant.invalidIndirectReference)
  ///     .setMessageParams([5, 0]);
  /// ```
  CraftPdfException setMessageParams(List<Object?> params) {
    var formattedMessage = message;
    for (var i = 0; i < params.length; i++) {
      formattedMessage =
          formattedMessage.replaceAll('{$i}', params[i]?.toString() ?? 'null');
    }
    return CraftPdfException(formattedMessage,
        cause: cause, pdfObject: pdfObject);
  }

  @override
  String toString() {
    final buffer = StringBuffer('PdfException: $message');
    if (pdfObject != null) {
      buffer.write('\nObject: $pdfObject');
    }
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}

/// Exception thrown when a bad password is provided for an encrypted PDF.
class CraftBadPasswordException extends CraftPdfException {
  CraftBadPasswordException(super.message, {super.cause});
}

/// Exception thrown when the PDF document is encrypted but no password was provided.
class EncryptedDocumentException extends CraftPdfException {
  EncryptedDocumentException(super.message, {super.cause});
}

/// Exception thrown when an invalid PDF structure is encountered.
class InvalidPdfException extends CraftPdfException {
  InvalidPdfException(super.message, {super.cause, super.pdfObject});
}

/// Exception thrown for XRef table/stream errors.
class XrefException extends CraftPdfException {
  XrefException(super.message, {super.cause});
}
