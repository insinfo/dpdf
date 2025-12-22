import 'package:dpdf/src/kernel/geom/rectangle.dart';

class LayoutArea {
  int pageNumber;
  Rectangle bBox;

  LayoutArea(this.pageNumber, this.bBox);

  int getPageNumber() {
    return pageNumber;
  }

  Rectangle getBBox() {
    return bBox;
  }

  void setBBox(Rectangle bbox) {
    this.bBox = bbox;
  }

  LayoutArea clone() {
    return LayoutArea(pageNumber, bBox.clone());
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LayoutArea &&
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
