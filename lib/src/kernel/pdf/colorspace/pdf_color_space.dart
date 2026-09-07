import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_device_cs.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_special_cs.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_cie_based_cs.dart';

/// Represents the most common properties of color spaces.
abstract class CraftPdfColorSpace
    extends CraftPdfObjectWrapper<CraftPdfObject> {
  static final Set<CraftPdfName> directColorSpaces = Set.unmodifiable({
    CraftPdfName.deviceGray,
    CraftPdfName.deviceRgb,
    CraftPdfName.deviceCmyk,
    CraftPdfName.pattern
  });

  CraftPdfColorSpace(CraftPdfObject pdfObject) : super(pdfObject);

  int getNumberOfComponents();

  /// Creates a [PdfColorSpace] from a [PdfObject].
  static Future<CraftPdfColorSpace?> makeColorSpace(
      CraftPdfObject? pdfObject) async {
    if (pdfObject == null) return null;

    // Resolve indirect reference if it is one
    if (pdfObject is CraftPdfIndirectReference) {
      pdfObject = await pdfObject.targetObject();
    }
    if (pdfObject == null) return null;

    // If array of size 1, unwrap
    if (pdfObject is CraftPdfArray && pdfObject.size() == 1) {
      pdfObject = await pdfObject.get(0);
    }

    if (CraftPdfName.deviceGray == pdfObject) {
      return PdfDeviceCsGray();
    } else if (CraftPdfName.deviceRgb == pdfObject) {
      return PdfDeviceCsRgb();
    } else if (CraftPdfName.deviceCmyk == pdfObject) {
      return PdfDeviceCsCmyk();
    } else if (CraftPdfName.pattern == pdfObject) {
      return PdfSpecialCsPattern();
    } else if (pdfObject is CraftPdfArray) {
      CraftPdfName? csType = await pdfObject.nameEntry(0);
      if (CraftPdfName.calGray == csType) {
        return PdfCieBasedCsCalGray(pdfObject);
      } else if (CraftPdfName.calRgb == csType) {
        return PdfCieBasedCsCalRgb(pdfObject);
      } else if (CraftPdfName.lab == csType) {
        return PdfCieBasedCsLab(pdfObject);
      } else if (CraftPdfName.iccBased == csType) {
        return PdfCieBasedCsIccBased(pdfObject);
      }
      // TODO: Indexed, Separation, DeviceN
    }

    return null;
  }

  CraftPdfName getName() {
    final definition = pdfRepresentation();
    if (definition is CraftPdfName) return definition;
    if (definition is CraftPdfArray) {
      final entries = definition.toListCopy();
      if (entries.isNotEmpty && entries.first is CraftPdfName) {
        return entries.first as CraftPdfName;
      }
    }
    throw StateError('The color space definition has no PDF family name.');
  }
}
