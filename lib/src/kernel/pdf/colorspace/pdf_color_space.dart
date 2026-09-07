import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_device_cs.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_special_cs.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_cie_based_cs.dart';

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

  /// Converts a colour of this space into sRGB.
  ///
  /// [components] holds [getNumberOfComponents] values in this space's own
  /// component ranges (see [getComponentRange]); the result holds red, green
  /// and blue in 0..1. Implementations are synchronous so that a rasterizer
  /// can call them per pixel; everything a space needs is resolved by
  /// [makeColorSpace].
  ///
  /// Throws [UnsupportedError] for `/Pattern`, which carries no colour of its
  /// own.
  List<double> toRgb(List<double> components);

  /// The range of component [index] in this space.
  ///
  /// This is the interval a sample of an image or an indexed lookup table maps
  /// onto, i.e. the default `/Decode` of clause 8.9.5.2. All spaces except Lab
  /// and Indexed use 0..1.
  List<double> getComponentRange(int index) => const <double>[0.0, 1.0];

  /// Clamps [value] into 0..1.
  static double clampUnit(double value) {
    if (value.isNaN) return 0.0;
    if (value < 0.0) return 0.0;
    if (value > 1.0) return 1.0;
    return value;
  }

  /// Reads component [index] of [components], falling back to 0.
  static double componentAt(List<double> components, int index) {
    return index < components.length ? components[index] : 0.0;
  }

  /// Creates a [PdfColorSpace] from a [PdfObject].
  static Future<PdfColorSpace?> makeColorSpace(PdfObject? pdfObject) async {
    if (pdfObject == null) return null;

    // Resolve indirect reference if it is one
    if (pdfObject is PdfIndirectReference) {
      pdfObject = await pdfObject.targetObject();
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
      return PdfSpecialCsPattern();
    } else if (pdfObject is PdfArray) {
      PdfName? csType = await pdfObject.nameEntry(0);
      if (PdfName.calGray == csType) {
        return PdfCieBasedCsCalGray(pdfObject);
      } else if (PdfName.calRgb == csType) {
        return PdfCieBasedCsCalRgb(pdfObject);
      } else if (PdfName.lab == csType) {
        return await PdfCieBasedCsLab.parseArray(pdfObject);
      } else if (PdfName.iccBased == csType) {
        return await PdfCieBasedCsIccBased.parseArray(pdfObject);
      } else if (PdfName.indexed == csType) {
        return await PdfSpecialCsIndexed.parseArray(pdfObject);
      } else if (PdfName.separation == csType) {
        return await PdfSpecialCsSeparation.parseArray(pdfObject);
      } else if (PdfName.deviceN == csType) {
        return await PdfSpecialCsDeviceN.parseArray(pdfObject);
      } else if (PdfName.pattern == csType) {
        // `[/Pattern base]` — an uncoloured pattern space; the base space
        // describes the colour the pattern is painted with.
        return PdfSpecialCsPattern.withBase(
            pdfObject, await makeColorSpace(await pdfObject.get(1)));
      }
    }

    return null;
  }

  PdfName getName() {
    final definition = pdfRepresentation();
    if (definition is PdfName) return definition;
    if (definition is PdfArray) {
      final entries = definition.toListCopy();
      if (entries.isNotEmpty && entries.first is PdfName) {
        return entries.first as PdfName;
      }
    }
    throw StateError('The color space definition has no PDF family name.');
  }
}
