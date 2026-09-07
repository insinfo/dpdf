import 'package:dpdf/src/kernel/colors/color.dart';

abstract class CraftBorder {
  static const int SOLID = 0;
  static const int DASHED = 1;

  double width;
  CraftColor? color;
  int type = SOLID;

  CraftBorder(this.width);

  // ignore: non_constant_identifier_names
  static final CraftBorder NO_BORDER = _NullBorder();
}

class CraftSolidBorder extends CraftBorder {
  CraftSolidBorder(super.width);
}

class _NullBorder extends CraftBorder {
  _NullBorder() : super(0);
}
