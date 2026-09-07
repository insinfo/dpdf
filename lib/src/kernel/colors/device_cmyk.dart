import 'dart:math';
import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/colors/device_rgb.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_device_cs.dart';

/// CMYK device color components.
class CraftDeviceCmyk extends CraftColor {
  static final CraftDeviceCmyk CYAN = CraftDeviceCmyk.fromInts(100, 0, 0, 0);
  static final CraftDeviceCmyk MAGENTA = CraftDeviceCmyk.fromInts(0, 100, 0, 0);
  static final CraftDeviceCmyk YELLOW = CraftDeviceCmyk.fromInts(0, 0, 100, 0);
  static final CraftDeviceCmyk BLACK = CraftDeviceCmyk.fromInts(0, 0, 0, 100);

  /// Creates DeviceCmyk color.
  CraftDeviceCmyk([double c = 0, double m = 0, double y = 0, double k = 1])
      : super(PdfDeviceCsCmyk(), [_clip(c), _clip(m), _clip(y), _clip(k)]);

  CraftDeviceCmyk.fromInts(int c, int m, int y, int k)
      : this(c / 100.0, m / 100.0, y / 100.0, k / 100.0);

  static double _clip(double value) {
    return value > 1 ? 1.0 : (value > 0 ? value : 0.0);
  }

  static CraftDeviceCmyk makeLighter(CraftDeviceCmyk cmykColor) {
    CraftDeviceRgb rgbEquivalent = _convertCmykToRgb(cmykColor);
    CraftDeviceRgb lighterRgb = CraftDeviceRgb.makeLighter(rgbEquivalent);
    return _convertRgbToCmyk(lighterRgb);
  }

  static CraftDeviceCmyk makeDarker(CraftDeviceCmyk cmykColor) {
    CraftDeviceRgb rgbEquivalent = _convertCmykToRgb(cmykColor);
    CraftDeviceRgb darkerRgb = CraftDeviceRgb.makeDarker(rgbEquivalent);
    return _convertRgbToCmyk(darkerRgb);
  }

  static CraftDeviceRgb _convertCmykToRgb(CraftDeviceCmyk cmykColor) {
    double c = cmykColor.getColorValue()[0];
    double m = cmykColor.getColorValue()[1];
    double y = cmykColor.getColorValue()[2];
    double k = cmykColor.getColorValue()[3];

    return CraftDeviceRgb(
        (1.0 - c) * (1.0 - k), (1.0 - m) * (1.0 - k), (1.0 - y) * (1.0 - k));
  }

  static CraftDeviceCmyk _convertRgbToCmyk(CraftDeviceRgb rgbColor) {
    double r = rgbColor.getColorValue()[0];
    double g = rgbColor.getColorValue()[1];
    double b = rgbColor.getColorValue()[2];

    double k = 1.0 - max(r, max(g, b));
    // Avoid division by zero
    if (k >= 1.0 - 1e-6) return CraftDeviceCmyk(0, 0, 0, 1);

    double c = (1.0 - r - k) / (1.0 - k);
    double m = (1.0 - g - k) / (1.0 - k);
    double y = (1.0 - b - k) / (1.0 - k);

    return CraftDeviceCmyk(c, m, y, k);
  }
}
