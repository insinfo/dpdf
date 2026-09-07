import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/colors/device_rgb.dart';

class CraftColorConstants {
  static final CraftColor BLACK = CraftDeviceRgb.BLACK;
  static final CraftColor WHITE = CraftDeviceRgb.WHITE;
  static final CraftColor RED = CraftDeviceRgb.RED;
  static final CraftColor GREEN = CraftDeviceRgb.GREEN;
  static final CraftColor BLUE = CraftDeviceRgb.BLUE;
  static final CraftColor CYAN = CraftDeviceRgb(0, 255, 255);
  static final CraftColor MAGENTA = CraftDeviceRgb(255, 0, 255);
  static final CraftColor YELLOW = CraftDeviceRgb(255, 255, 0);
  static final CraftColor GRAY = CraftDeviceRgb(128, 128, 128);
  static final CraftColor LIGHT_GRAY = CraftDeviceRgb(192, 192, 192);
  static final CraftColor DARK_GRAY = CraftDeviceRgb(64, 64, 64);
  static final CraftColor ORANGE = CraftDeviceRgb(255, 200, 0);
  static final CraftColor PINK = CraftDeviceRgb(255, 175, 175);
}
