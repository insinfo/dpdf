import 'dart:math';
import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/colors/device_rgb.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_device_cs.dart';

/// Color space to specify colors according to CMYK color model.
class DeviceCmyk extends Color {
  static final DeviceCmyk CYAN = DeviceCmyk.fromInts(100, 0, 0, 0);
  static final DeviceCmyk MAGENTA = DeviceCmyk.fromInts(0, 100, 0, 0);
  static final DeviceCmyk YELLOW = DeviceCmyk.fromInts(0, 0, 100, 0);
  static final DeviceCmyk BLACK = DeviceCmyk.fromInts(0, 0, 0, 100);

  /// Creates DeviceCmyk color.
  DeviceCmyk([double c = 0, double m = 0, double y = 0, double k = 1])
      : super(PdfDeviceCsCmyk(), [_clip(c), _clip(m), _clip(y), _clip(k)]);

  DeviceCmyk.fromInts(int c, int m, int y, int k)
      : this(c / 100.0, m / 100.0, y / 100.0, k / 100.0);

  static double _clip(double value) {
    return value > 1 ? 1.0 : (value > 0 ? value : 0.0);
  }

  static DeviceCmyk makeLighter(DeviceCmyk cmykColor) {
    DeviceRgb rgbEquivalent = _convertCmykToRgb(cmykColor);
    DeviceRgb lighterRgb = DeviceRgb.makeLighter(rgbEquivalent);
    return _convertRgbToCmyk(lighterRgb);
  }

  static DeviceCmyk makeDarker(DeviceCmyk cmykColor) {
    DeviceRgb rgbEquivalent = _convertCmykToRgb(cmykColor);
    DeviceRgb darkerRgb = DeviceRgb.makeDarker(rgbEquivalent);
    return _convertRgbToCmyk(darkerRgb);
  }

  static DeviceRgb _convertCmykToRgb(DeviceCmyk cmykColor) {
    double c = cmykColor.getColorValue()[0];
    double m = cmykColor.getColorValue()[1];
    double y = cmykColor.getColorValue()[2];
    double k = cmykColor.getColorValue()[3];

    return DeviceRgb(
        (1.0 - c) * (1.0 - k), (1.0 - m) * (1.0 - k), (1.0 - y) * (1.0 - k));
  }

  static DeviceCmyk _convertRgbToCmyk(DeviceRgb rgbColor) {
    double r = rgbColor.getColorValue()[0];
    double g = rgbColor.getColorValue()[1];
    double b = rgbColor.getColorValue()[2];

    double k = 1.0 - max(r, max(g, b));
    // Avoid division by zero
    if (k >= 1.0 - 1e-6) return DeviceCmyk(0, 0, 0, 1);

    double c = (1.0 - r - k) / (1.0 - k);
    double m = (1.0 - g - k) / (1.0 - k);
    double y = (1.0 - b - k) / (1.0 - k);

    return DeviceCmyk(c, m, y, k);
  }
}
