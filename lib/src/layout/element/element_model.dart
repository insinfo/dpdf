import 'package:dpdf/src/layout/element/element.dart';

abstract class CraftElementModel implements CraftElement {
  List<CraftElement> getChildren();
}
