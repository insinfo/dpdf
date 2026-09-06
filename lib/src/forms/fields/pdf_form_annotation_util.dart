import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_page.dart';
import '../../kernel/pdf/annot/pdf_annotation.dart';
import 'pdf_form_field.dart';
import '../../kernel/pdf/pdf_array.dart';

class CraftPdfFormAnnotationUtil {
  CraftPdfFormAnnotationUtil._();

  static Future<bool> isPureWidgetOrMergedField(
      CraftPdfDictionary fieldDict) async {
    // Check subtype
    CraftPdfName? subtype = await fieldDict.nameEntry(CraftPdfName.subtype);
    return CraftPdfName.widget == subtype;
  }

  static Future<bool> isPureWidget(CraftPdfDictionary fieldDict) async {
    // A pure widget is a Widget annotation that is NOT partially a form field
    // But in PDF, merged fields (dict has both widget and field keys) are common.
    // The C# logic says: IsPureWidgetOrMergedField && !IsFormField
    // IsFormField usually checks for FT (Field Type) or Parent.

    if (!(await isPureWidgetOrMergedField(fieldDict))) return false;

    // Check if it has FT (Field Type), which would make it a Field
    if (fieldDict.containsKey(CraftPdfName.ft)) return false;

    return true;
  }

  static Future<void> addWidgetAnnotationToPage(
      CraftPdfPage page, CraftPdfAnnotation annotation,
      [int index = -1]) async {
    CraftPdfArray? annots =
        await page.pdfRepresentation().arrayEntry(CraftPdfName.annots);
    if (annots != null &&
        await annots.containsObject(annotation.pdfRepresentation())) {
      return;
    }
    // Tagging logic omitted for now
    await page.addAnnotation(
        annotation); // Index support needs update in PdfPage if strictly required
  }

  static Future<void> mergeWidgetWithParentField(
      CraftPdfFormField field) async {
    CraftPdfArray? kids = await field.getKids();
    if (kids != null && kids.size() == 1) {
      CraftPdfDictionary? kidDict = await kids.dictionaryEntry(0);
      if (kidDict != null && await isPureWidget(kidDict)) {
        kidDict.remove(CraftPdfName.parent);
        field.pdfRepresentation().mergeDifferent(kidDict);
        // field.removeChildren(); // Need usage
        // kidRef setFree?

        // This logic is complex because it involves structural changes.
        // For now, we will leave this as a stub to allow compilation of calls.
      }
    }
  }
}
