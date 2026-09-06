import 'rectangle.dart';

class CraftPageSize extends CraftRectangle {
  static final CraftPageSize A0 = CraftPageSize(2384, 3370);
  static final CraftPageSize A1 = CraftPageSize(1684, 2384);
  static final CraftPageSize A2 = CraftPageSize(1190, 1684);
  static final CraftPageSize A3 = CraftPageSize(842, 1190);
  static final CraftPageSize A4 = CraftPageSize(595, 842);
  static final CraftPageSize A5 = CraftPageSize(420, 595);
  static final CraftPageSize A6 = CraftPageSize(298, 420);
  static final CraftPageSize A7 = CraftPageSize(210, 298);
  static final CraftPageSize A8 = CraftPageSize(148, 210);
  static final CraftPageSize A9 = CraftPageSize(105, 148);
  static final CraftPageSize A10 = CraftPageSize(74, 105);

  static final CraftPageSize B0 = CraftPageSize(2834, 4008);
  static final CraftPageSize B1 = CraftPageSize(2004, 2834);
  static final CraftPageSize B2 = CraftPageSize(1417, 2004);
  static final CraftPageSize B3 = CraftPageSize(1000, 1417);
  static final CraftPageSize B4 = CraftPageSize(708, 1000);
  static final CraftPageSize B5 = CraftPageSize(498, 708);
  static final CraftPageSize B6 = CraftPageSize(354, 498);
  static final CraftPageSize B7 = CraftPageSize(249, 354);
  static final CraftPageSize B8 = CraftPageSize(175, 249);
  static final CraftPageSize B9 = CraftPageSize(124, 175);
  static final CraftPageSize B10 = CraftPageSize(88, 124);

  static final CraftPageSize defaultSize = A4;

  static final CraftPageSize executive = CraftPageSize(522, 756);
  static final CraftPageSize ledger = CraftPageSize(1224, 792);
  static final CraftPageSize legal = CraftPageSize(612, 1008);
  static final CraftPageSize letter = CraftPageSize(612, 792);
  static final CraftPageSize tabloid = CraftPageSize(792, 1224);

  CraftPageSize(double width, double height) : super(0, 0, width, height);

  CraftPageSize.fromRectangle(CraftRectangle box)
      : super(box.x, box.y, box.width, box.height);

  /// Rotates clockwise.
  CraftPageSize rotate() {
    return CraftPageSize(height, width);
  }
}
