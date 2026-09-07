import 'package:dpdf/src/commons/utils/value_collections.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_color_space.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_device_cs.dart';
import 'package:dpdf/src/kernel/colors/device_gray.dart';
import 'package:dpdf/src/kernel/colors/device_rgb.dart';
import 'package:dpdf/src/kernel/colors/device_cmyk.dart';

/// Represents a color.
class CraftColor {
  /// The color space of the color.
  final CraftPdfColorSpace colorSpace;

  /// The color value of the color.
  List<double> colorValue;

  /// Creates a Color of certain color space and color value.
  CraftColor(this.colorSpace, List<double>? colorValue)
      : colorValue =
            colorValue ?? List.filled(colorSpace.getNumberOfComponents(), 0.0);

  static CraftColor? makeColor(CraftPdfColorSpace colorSpace,
      [List<double>? colorValue]) {
    if (colorSpace is PdfDeviceCsGray) {
      return colorValue != null
          ? CraftDeviceGray(colorValue[0])
          : CraftDeviceGray();
    } else if (colorSpace is PdfDeviceCsRgb) {
      return colorValue != null && colorValue.length >= 3
          ? CraftDeviceRgb(colorValue[0], colorValue[1], colorValue[2])
          : CraftDeviceRgb();
    } else if (colorSpace is PdfDeviceCsCmyk) {
      return colorValue != null && colorValue.length >= 4
          ? CraftDeviceCmyk(
              colorValue[0], colorValue[1], colorValue[2], colorValue[3])
          : CraftDeviceCmyk();
    }
    // Generic color
    return CraftColor(colorSpace, colorValue);
  }

  static CraftColor? createColorWithColorSpace(List<double>? colorValue) {
    if (colorValue == null || colorValue.isEmpty) return null;
    if (colorValue.length == 1) return CraftDeviceGray(colorValue[0]);
    if (colorValue.length == 3)
      return CraftDeviceRgb(colorValue[0], colorValue[1], colorValue[2]);
    if (colorValue.length == 4)
      return CraftDeviceCmyk(
          colorValue[0], colorValue[1], colorValue[2], colorValue[3]);
    return null;
  }

  int getNumberOfComponents() => colorValue.length;

  CraftPdfColorSpace getColorSpace() => colorSpace;

  List<double> getColorValue() => colorValue;

  void setColorValue(List<double> value) {
    if (value.length != colorValue.length) {
      throw ArgumentError('Incorrect number of components');
    }
    colorValue = value;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CraftColor) return false;

    final csEq =
        colorSpace.pdfRepresentation() == other.colorSpace.pdfRepresentation();
    return csEq && ValueCollections.listsEqual(colorValue, other.colorValue);
  }

  @override
  int get hashCode => Object.hash(
      colorSpace.pdfRepresentation(), ValueCollections.listHash(colorValue));
}
