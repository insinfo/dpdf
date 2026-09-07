import 'package:dpdf/src/layout/element/element.dart';

abstract class ElementModel implements Element {
  List<Element> getChildren();
}
