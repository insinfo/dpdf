import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';

class PdfShading extends PdfObjectWrapper<PdfDictionary> {
  PdfShading(PdfDictionary pdfObject) : super(pdfObject);

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  static PdfShading createAxial(PdfName colorSpace, double x0, double y0,
      double x1, double y1, List<double> coords, PdfObject function) {
    PdfDictionary dict = PdfDictionary();
    dict.put(PdfName.shadingType, PdfNumber(2)); // Axial
    dict.put(PdfName.colorSpace, colorSpace);
    dict.put(PdfName.coords, PdfArray.fromDoubles([x0, y0, x1, y1]));
    dict.put(PdfName.function, function);
    return PdfShading(dict);
  }

  static PdfShading createRadial(PdfName colorSpace, double x0, double y0,
      double r0, double x1, double y1, double r1, PdfObject function) {
    PdfDictionary dict = PdfDictionary();
    dict.put(PdfName.shadingType, PdfNumber(3)); // Radial
    dict.put(PdfName.colorSpace, colorSpace);
    dict.put(PdfName.coords, PdfArray.fromDoubles([x0, y0, r0, x1, y1, r1]));
    dict.put(PdfName.function, function);
    return PdfShading(dict);
  }
}
