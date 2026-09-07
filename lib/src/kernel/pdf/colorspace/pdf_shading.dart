import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';

class CraftPdfShading extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  CraftPdfShading(CraftPdfDictionary pdfObject) : super(pdfObject);

  @override
  bool requiresIndirectStorage() => true;

  static CraftPdfShading createAxial(
      CraftPdfName colorSpace,
      double x0,
      double y0,
      double x1,
      double y1,
      List<double> coords,
      CraftPdfObject function) {
    CraftPdfDictionary dict = CraftPdfDictionary();
    dict.put(CraftPdfName.shadingType, CraftPdfNumber(2)); // Axial
    dict.put(CraftPdfName.colorSpace, colorSpace);
    dict.put(CraftPdfName.coords, CraftPdfArray.fromDoubles([x0, y0, x1, y1]));
    dict.put(CraftPdfName.function, function);
    return CraftPdfShading(dict);
  }

  static CraftPdfShading createRadial(
      CraftPdfName colorSpace,
      double x0,
      double y0,
      double r0,
      double x1,
      double y1,
      double r1,
      CraftPdfObject function) {
    CraftPdfDictionary dict = CraftPdfDictionary();
    dict.put(CraftPdfName.shadingType, CraftPdfNumber(3)); // Radial
    dict.put(CraftPdfName.colorSpace, colorSpace);
    dict.put(CraftPdfName.coords,
        CraftPdfArray.fromDoubles([x0, y0, r0, x1, y1, r1]));
    dict.put(CraftPdfName.function, function);
    return CraftPdfShading(dict);
  }
}
