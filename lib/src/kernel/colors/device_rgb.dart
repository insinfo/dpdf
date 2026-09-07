import 'dart:math';
import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_device_cs.dart';

/// RGB device color components.
class DeviceRgb extends Color {
  static final DeviceRgb BLACK = DeviceRgb.fromInts(0, 0, 0);
  static final DeviceRgb WHITE = DeviceRgb.fromInts(255, 255, 255);
  static final DeviceRgb RED = DeviceRgb.fromInts(255, 0, 0);
  static final DeviceRgb GREEN = DeviceRgb.fromInts(0, 255, 0);
  static final DeviceRgb BLUE = DeviceRgb.fromInts(0, 0, 255);

  /// Initializes RGB from red, green and blue component intensities.
  DeviceRgb([double r = 0, double g = 0, double b = 0])
      : super(PdfDeviceCsRgb(), [_clip(r), _clip(g), _clip(b)]);

  /// Initializes RGB from red, green and blue component intensities.
  DeviceRgb.fromInts(int r, int g, int b)
      : this(r / 255.0, g / 255.0, b / 255.0);

  static double _clip(double value) {
    return value > 1 ? 1.0 : (value > 0 ? value : 0.0);
  }

  static DeviceRgb makeLighter(DeviceRgb rgbColor) {
    double r = rgbColor.getColorValue()[0];
    double g = rgbColor.getColorValue()[1];
    double b = rgbColor.getColorValue()[2];
    double v = max(r, max(g, b));
    if (v == 0.0) {
      return DeviceRgb.fromInts(0x54, 0x54, 0x54);
    }
    double multiplier = min(1.0, v + 0.33) / v;
    return DeviceRgb(r * multiplier, g * multiplier, b * multiplier);
  }

  static DeviceRgb makeDarker(DeviceRgb rgbColor) {
    double r = rgbColor.getColorValue()[0];
    double g = rgbColor.getColorValue()[1];
    double b = rgbColor.getColorValue()[2];
    double v = max(r, max(g, b));
    double multiplier = max(0.0, (v - 0.33) / v);
    return DeviceRgb(r * multiplier, g * multiplier, b * multiplier);
  }
}
