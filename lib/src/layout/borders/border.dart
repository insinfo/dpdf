import 'package:dpdf/src/kernel/colors/color.dart';

abstract class Border {
  static const int SOLID = 0;
  static const int DASHED = 1;

  double width;
  Color? color;
  int type = SOLID;

  Border(this.width);

  // ignore: non_constant_identifier_names
  static final Border NO_BORDER = _NullBorder();
}

class SolidBorder extends Border {
  SolidBorder(double width) : super(width);
}

class _NullBorder extends Border {
  _NullBorder() : super(0);
}
