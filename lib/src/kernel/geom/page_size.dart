import 'rectangle.dart';

class PageSize extends Rectangle {
  static final PageSize A0 = PageSize(2384, 3370);
  static final PageSize A1 = PageSize(1684, 2384);
  static final PageSize A2 = PageSize(1190, 1684);
  static final PageSize A3 = PageSize(842, 1190);
  static final PageSize A4 = PageSize(595, 842);
  static final PageSize A5 = PageSize(420, 595);
  static final PageSize A6 = PageSize(298, 420);
  static final PageSize A7 = PageSize(210, 298);
  static final PageSize A8 = PageSize(148, 210);
  static final PageSize A9 = PageSize(105, 148);
  static final PageSize A10 = PageSize(74, 105);

  static final PageSize B0 = PageSize(2834, 4008);
  static final PageSize B1 = PageSize(2004, 2834);
  static final PageSize B2 = PageSize(1417, 2004);
  static final PageSize B3 = PageSize(1000, 1417);
  static final PageSize B4 = PageSize(708, 1000);
  static final PageSize B5 = PageSize(498, 708);
  static final PageSize B6 = PageSize(354, 498);
  static final PageSize B7 = PageSize(249, 354);
  static final PageSize B8 = PageSize(175, 249);
  static final PageSize B9 = PageSize(124, 175);
  static final PageSize B10 = PageSize(88, 124);

  static final PageSize defaultSize = A4;

  static final PageSize executive = PageSize(522, 756);
  static final PageSize ledger = PageSize(1224, 792);
  static final PageSize legal = PageSize(612, 1008);
  static final PageSize letter = PageSize(612, 792);
  static final PageSize tabloid = PageSize(792, 1224);

  PageSize(double width, double height) : super(0, 0, width, height);

  PageSize.fromRectangle(Rectangle box)
      : super(box.x, box.y, box.width, box.height);

  /// Rotates clockwise.
  PageSize rotate() {
    return PageSize(height, width);
  }
}
