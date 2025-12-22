import 'package:collection/collection.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_color_space.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_device_cs.dart';
import 'package:dpdf/src/kernel/colors/device_gray.dart';
import 'package:dpdf/src/kernel/colors/device_rgb.dart';
import 'package:dpdf/src/kernel/colors/device_cmyk.dart';

/// Represents a color.
class Color {
  /// The color space of the color.
  final PdfColorSpace colorSpace;

  /// The color value of the color.
  List<double> colorValue;

  /// Creates a Color of certain color space and color value.
  Color(this.colorSpace, List<double>? colorValue)
      : colorValue =
            colorValue ?? List.filled(colorSpace.getNumberOfComponents(), 0.0);

  static Color? makeColor(PdfColorSpace colorSpace,
      [List<double>? colorValue]) {
    if (colorSpace is PdfDeviceCsGray) {
      return colorValue != null ? DeviceGray(colorValue[0]) : DeviceGray();
    } else if (colorSpace is PdfDeviceCsRgb) {
      return colorValue != null && colorValue.length >= 3
          ? DeviceRgb(colorValue[0], colorValue[1], colorValue[2])
          : DeviceRgb();
    } else if (colorSpace is PdfDeviceCsCmyk) {
      return colorValue != null && colorValue.length >= 4
          ? DeviceCmyk(
              colorValue[0], colorValue[1], colorValue[2], colorValue[3])
          : DeviceCmyk();
    }
    // TODO: Other color spaces
    return null;
  }

  static Color? createColorWithColorSpace(List<double>? colorValue) {
    if (colorValue == null || colorValue.isEmpty) return null;
    if (colorValue.length == 1) return DeviceGray(colorValue[0]);
    if (colorValue.length == 3)
      return DeviceRgb(colorValue[0], colorValue[1], colorValue[2]);
    if (colorValue.length == 4)
      return DeviceCmyk(
          colorValue[0], colorValue[1], colorValue[2], colorValue[3]);
    return null;
  }

  int getNumberOfComponents() => colorValue.length;

  PdfColorSpace getColorSpace() => colorSpace;

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
    if (other is! Color) return false;

    final csEq = colorSpace.getPdfObject() == other.colorSpace.getPdfObject();
    return csEq && const ListEquality().equals(colorValue, other.colorValue);
  }

  @override
  int get hashCode => Object.hash(
      colorSpace.getPdfObject(), const ListEquality().hash(colorValue));
}
