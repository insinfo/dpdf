import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_device_cs.dart';

/// Represents the most common properties of color spaces.
abstract class PdfColorSpace extends PdfObjectWrapper<PdfObject> {
  static final Set<PdfName> directColorSpaces = Set.unmodifiable({
    PdfName.deviceGray,
    PdfName.deviceRgb,
    PdfName.deviceCmyk,
    PdfName.pattern
  });

  PdfColorSpace(PdfObject pdfObject) : super(pdfObject);

  int getNumberOfComponents();

  /// Creates a [PdfColorSpace] from a [PdfObject].
  static Future<PdfColorSpace?> makeColorSpace(PdfObject? pdfObject) async {
    if (pdfObject == null) return null;

    // Resolve indirect reference if it is one
    if (pdfObject is PdfIndirectReference) {
      pdfObject = await pdfObject.getRefersTo();
    }
    if (pdfObject == null) return null;

    // If array of size 1, unwrap
    if (pdfObject is PdfArray && pdfObject.size() == 1) {
      pdfObject = await pdfObject.get(0);
    }

    if (PdfName.deviceGray == pdfObject) {
      return PdfDeviceCsGray();
    } else if (PdfName.deviceRgb == pdfObject) {
      return PdfDeviceCsRgb();
    } else if (PdfName.deviceCmyk == pdfObject) {
      return PdfDeviceCsCmyk();
    } else if (PdfName.pattern == pdfObject) {
      // return PdfSpecialCsPattern();
      return null; // TODO
    } else if (pdfObject is PdfArray) {
      /*
      PdfName? csType = await pdfObject.getAsName(0);
      if (PdfName.calGray == csType) {
        return PdfCieBasedCsCalGray(pdfObject);
      }
      // ...
      */
    }

    return null;
  }

  PdfName getName() {
    return PdfName(runtimeType.toString());
  }
}
