import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/colors/device_rgb.dart';

class ColorConstants {
  static final Color BLACK = DeviceRgb.BLACK;
  static final Color WHITE = DeviceRgb.WHITE;
  static final Color RED = DeviceRgb.RED;
  static final Color GREEN = DeviceRgb.GREEN;
  static final Color BLUE = DeviceRgb.BLUE;
  static final Color CYAN = DeviceRgb(0, 255, 255);
  static final Color MAGENTA = DeviceRgb(255, 0, 255);
  static final Color YELLOW = DeviceRgb(255, 255, 0);
  static final Color GRAY = DeviceRgb(128, 128, 128);
  static final Color LIGHT_GRAY = DeviceRgb(192, 192, 192);
  static final Color DARK_GRAY = DeviceRgb(64, 64, 64);
  static final Color ORANGE = DeviceRgb(255, 200, 0);
  static final Color PINK = DeviceRgb(255, 175, 175);
}
