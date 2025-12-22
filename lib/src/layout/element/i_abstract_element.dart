import 'package:dpdf/src/layout/element/i_element.dart';

abstract class IAbstractElement implements IElement {
  List<IElement> getChildren();
}
