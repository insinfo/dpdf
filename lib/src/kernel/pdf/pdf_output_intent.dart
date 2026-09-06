import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_string.dart';
import 'pdf_stream.dart';
import 'pdf_object_wrapper.dart';

/// Represents a PDF Output Intent.
class CraftPdfOutputIntent extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  CraftPdfOutputIntent(CraftPdfDictionary pdfObject) : super(pdfObject);

  factory CraftPdfOutputIntent.create(
    String outputConditionIdentifier,
    String? outputCondition,
    String? registryName,
    String? info,
    CraftPdfStream? destOutputProfile,
  ) {
    final dict = CraftPdfDictionary();
    dict.put(CraftPdfName.type, CraftPdfName.outputIntent);
    dict.put(CraftPdfName.s, CraftPdfName.gts_pdfa1);
    dict.put(CraftPdfName.outputConditionIdentifier,
        CraftPdfString(outputConditionIdentifier));

    if (outputCondition != null) {
      dict.put(CraftPdfName.outputCondition, CraftPdfString(outputCondition));
    }
    if (registryName != null) {
      dict.put(CraftPdfName.registryName, CraftPdfString(registryName));
    }
    if (info != null) {
      dict.put(CraftPdfName.intern('Info'), CraftPdfString(info));
    }
    if (destOutputProfile != null) {
      dict.put(CraftPdfName.destOutputProfile, destOutputProfile);
    }

    return CraftPdfOutputIntent(dict);
  }

  @override
  bool requiresIndirectStorage() => true;
}
