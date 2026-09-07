import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'pdf_action_uri.dart';
import 'pdf_action_goto.dart';

/// Represents a PDF Action.
class CraftPdfAction extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  CraftPdfAction(CraftPdfDictionary pdfObject) : super(pdfObject);

  @override
  bool requiresIndirectStorage() => true;

  /// Sets an additional action to the annotation/field.
  static Future<void> setAdditionalAction(
      CraftPdfObjectWrapper<CraftPdfDictionary> wrapper,
      CraftPdfName key,
      CraftPdfAction action) async {
    CraftPdfDictionary? aa = await wrapper
        .pdfRepresentation()
        .dictionaryEntry(CraftPdfName.aa); // AA = Additional Actions
    if (aa == null) {
      aa = CraftPdfDictionary();
      wrapper.pdfRepresentation().put(CraftPdfName.aa, aa);
    }
    aa.put(key, action.pdfRepresentation());
    action.markChanged();
    wrapper.markChanged();
  }

  /// Factory method to create a PdfAction from a dictionary.
  static Future<CraftPdfAction> makeAction(
      CraftPdfDictionary dictionary) async {
    final s = await dictionary.nameEntry(CraftPdfName.s);
    if (CraftPdfName.uri == s) {
      return PdfActionURI(dictionary);
    } else if (CraftPdfName.goTo == s) {
      return PdfActionGoTo(dictionary);
    }
    return CraftPdfAction(dictionary);
  }
}
