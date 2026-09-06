import 'package:pdfcraft/src/kernel/geom/rectangle.dart';

class CraftLayoutArea {
  int pageNumber;
  CraftRectangle bBox;

  CraftLayoutArea(this.pageNumber, this.bBox);

  int pageOrdinal() {
    return pageNumber;
  }

  CraftRectangle getBBox() {
    return bBox;
  }

  void setBBox(CraftRectangle bbox) {
    this.bBox = bbox;
  }

  CraftLayoutArea clone() {
    return CraftLayoutArea(pageNumber, bBox.clone());
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CraftLayoutArea &&
        pageNumber == other.pageNumber &&
        bBox.equalsWithEpsilon(other.bBox);
  }

  @override
  int get hashCode => pageNumber.hashCode ^ bBox.hashCode;

  @override
  String toString() {
    return "$bBox, page $pageNumber";
  }
}
