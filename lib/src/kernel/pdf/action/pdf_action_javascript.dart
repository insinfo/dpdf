import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'pdf_action.dart';

/// JavaScript action.
///
/// See ISO 32000-1:2008, 12.6.4.16, Table 217.
class PdfActionJavaScript extends PdfAction {
  PdfActionJavaScript(super.pdfObject);

  /// Creates a `/JavaScript` action carrying the script as a text string.
  PdfActionJavaScript.create(String script) : super.ofType(PdfName.javaScript) {
    pdfRepresentation().put(PdfName.js, PdfString(script));
  }

  /// Creates a `/JavaScript` action carrying the script as a text stream,
  /// the alternative form allowed by Table 217 for long scripts.
  PdfActionJavaScript.fromStream(PdfStream script)
      : super.ofType(PdfName.javaScript) {
    pdfRepresentation().put(PdfName.js, script);
  }

  /// Gets `/JS` as written; it is a text string or a text stream.
  Future<PdfObject?> getScriptObject() async =>
      await pdfRepresentation().get(PdfName.js, true);

  /// Gets the script text, decoding both the string and the stream forms.
  Future<String?> getScript() async {
    final value = await getScriptObject();
    if (value is PdfStream) {
      final bytes = await value.getBytes();
      if (bytes == null) return null;
      return PdfString.fromBytes(bytes).decodeMappingText();
    }
    if (value is PdfString) return value.decodeMappingText();
    return null;
  }
}
