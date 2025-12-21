import 'dart:math';
import 'package:itext/src/kernel/colors/color.dart';
import 'package:itext/src/kernel/pdf/colorspace/pdf_device_cs.dart';

/// Color space to specify shades of gray color.
class DeviceGray extends Color {
  /// Predefined white DeviceGray color.
  static final DeviceGray WHITE = DeviceGray(1.0);

  /// Predefined gray DeviceGray color.
  static final DeviceGray GRAY = DeviceGray(0.5);

  /// Predefined black DeviceGray color.
  static final DeviceGray BLACK = DeviceGray(0.0);

  /// Creates DeviceGray color by given grayscale.
  DeviceGray([double value = 0.0]) : super(PdfDeviceCsGray(), [_clip(value)]);

  static double _clip(double value) {
    return value > 1 ? 1.0 : (value > 0 ? value : 0.0);
  }

  /// Returns DeviceGray color which is lighter than given one.
  static DeviceGray makeLighter(DeviceGray grayColor) {
    double v = grayColor.getColorValue()[0];
    if (v == 0.0) {
      return DeviceGray(0.3);
    }
    double multiplier = min(1.0, v + 0.33) / v;
    return DeviceGray(v * multiplier);
  }

  /// Returns DeviceGray color which is darker than given one.
  static DeviceGray makeDarker(DeviceGray grayColor) {
    double v = grayColor.getColorValue()[0];
    double multiplier = max(0.0, (v - 0.33) / v);
    return DeviceGray(v * multiplier);
  }
}
