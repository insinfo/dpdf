import 'dart:math';
import 'package:pdfcraft/src/kernel/colors/color.dart';
import 'package:pdfcraft/src/kernel/pdf/colorspace/pdf_device_cs.dart';

/// Color space to specify shades of gray color.
class CraftDeviceGray extends CraftColor {
  /// Predefined white DeviceGray color.
  static final CraftDeviceGray WHITE = CraftDeviceGray(1.0);

  /// Predefined gray DeviceGray color.
  static final CraftDeviceGray GRAY = CraftDeviceGray(0.5);

  /// Predefined black DeviceGray color.
  static final CraftDeviceGray BLACK = CraftDeviceGray(0.0);

  /// Creates DeviceGray color by given grayscale.
  CraftDeviceGray([double value = 0.0])
      : super(PdfDeviceCsGray(), [_clip(value)]);

  static double _clip(double value) {
    return value > 1 ? 1.0 : (value > 0 ? value : 0.0);
  }

  /// Returns DeviceGray color which is lighter than given one.
  static CraftDeviceGray makeLighter(CraftDeviceGray grayColor) {
    double v = grayColor.getColorValue()[0];
    if (v == 0.0) {
      return CraftDeviceGray(0.3);
    }
    double multiplier = min(1.0, v + 0.33) / v;
    return CraftDeviceGray(v * multiplier);
  }

  /// Returns DeviceGray color which is darker than given one.
  static CraftDeviceGray makeDarker(CraftDeviceGray grayColor) {
    double v = grayColor.getColorValue()[0];
    double multiplier = max(0.0, (v - 0.33) / v);
    return CraftDeviceGray(v * multiplier);
  }
}
