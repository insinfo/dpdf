import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'pdf_action.dart';

/// Rendition action, controlling the playing of multimedia content.
///
/// See ISO 32000-1:2008, 12.6.4.13, Table 214.
class PdfActionRendition extends PdfAction {
  /// `/OP` 0: play the rendition of `/R`, associating it with `/AN`.
  static const int operationPlayNew = 0;

  /// `/OP` 1: stop the rendition played with `/AN` and drop the association.
  static const int operationStop = 1;

  /// `/OP` 2: pause the rendition played with `/AN`.
  static const int operationPause = 2;

  /// `/OP` 3: resume the rendition played with `/AN`.
  static const int operationResume = 3;

  /// `/OP` 4: play the rendition of `/R`, resuming when already paused.
  static const int operationPlay = 4;

  PdfActionRendition(super.pdfObject);

  /// Creates a `/Rendition` action driven by `/OP`.
  ///
  /// Table 214 requires `/R` for operations 0 and 4, and `/AN` for
  /// operations 0 to 4; both requirements are enforced here.
  PdfActionRendition.withOperation(int operation,
      {PdfDictionary? rendition, PdfDictionary? screenAnnotation})
      : super.ofType(PdfName.intern('Rendition')) {
    if (operation < operationPlayNew || operation > operationPlay) {
      throw ArgumentError.value(
          operation, 'operation', 'Rendition /OP shall lie in [0, 4]');
    }
    if ((operation == operationPlayNew || operation == operationPlay) &&
        rendition == null) {
      throw ArgumentError('Rendition /R is required when /OP is 0 or 4');
    }
    if (screenAnnotation == null) {
      throw ArgumentError('Rendition /AN is required when /OP is present');
    }
    pdfRepresentation().put(PdfName.intern('OP'), PdfNumber.fromInt(operation));
    if (rendition != null) {
      pdfRepresentation().put(PdfName.r, rendition);
    }
    pdfRepresentation().put(PdfName.intern('AN'), screenAnnotation);
  }

  /// Creates a `/Rendition` action driven by a JavaScript script, the form
  /// Table 214 allows when `/OP` is absent.
  PdfActionRendition.withScript(String script)
      : super.ofType(PdfName.intern('Rendition')) {
    pdfRepresentation().put(PdfName.js, PdfString(script));
  }

  /// Creates a `/Rendition` action driven by a JavaScript stream.
  PdfActionRendition.withScriptStream(PdfStream script)
      : super.ofType(PdfName.intern('Rendition')) {
    pdfRepresentation().put(PdfName.js, script);
  }

  /// Gets `/OP`.
  Future<int?> getOperation() async =>
      await pdfRepresentation().integerEntry(PdfName.intern('OP'));

  /// Gets `/R`, the rendition object.
  Future<PdfDictionary?> getRendition() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.r);

  /// Gets `/AN`, the screen annotation.
  Future<PdfDictionary?> getScreenAnnotation() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('AN'));

  /// Gets `/JS` as written; it is a text string or a stream.
  Future<PdfObject?> getScript() async =>
      await pdfRepresentation().get(PdfName.js, true);
}
