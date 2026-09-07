import 'package:dpdf/src/layout/layout/layout_area.dart';

class CraftRootLayoutArea extends CraftLayoutArea {
  CraftRootLayoutArea(super.pageNumber, super.bBox);

  // Clone needs to return RootLayoutArea?
  @override
  CraftLayoutArea clone() {
    return CraftRootLayoutArea(pageNumber, bBox.clone());
  }
}
