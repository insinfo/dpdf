import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_string.dart';
import 'pdf_stream.dart';
import 'pdf_object_wrapper.dart';

/// Represents a PDF Output Intent.
class PdfOutputIntent extends PdfObjectWrapper<PdfDictionary> {
  PdfOutputIntent(PdfDictionary pdfObject) : super(pdfObject);

  factory PdfOutputIntent.create(
    String outputConditionIdentifier,
    String? outputCondition,
    String? registryName,
    String? info,
    PdfStream? destOutputProfile,
  ) {
    final dict = PdfDictionary();
    dict.put(PdfName.type, PdfName.outputIntent);
    dict.put(PdfName.s, PdfName.gts_pdfa1);
    dict.put(PdfName.outputConditionIdentifier, PdfString(outputConditionIdentifier));

    if (outputCondition != null) {
      dict.put(PdfName.outputCondition, PdfString(outputCondition));
    }
    if (registryName != null) {
      dict.put(PdfName.registryName, PdfString(registryName));
    }
    if (info != null) {
      dict.put(PdfName.intern('Info'), PdfString(info));
    }
    if (destOutputProfile != null) {
      dict.put(PdfName.destOutputProfile, destOutputProfile);
    }

    return PdfOutputIntent(dict);
  }

  @override
  bool isWrappedObjectMustBeIndirect() => true;
}
