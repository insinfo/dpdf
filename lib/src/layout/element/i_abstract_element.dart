import 'package:itext/src/layout/element/i_element.dart';

abstract class IAbstractElement implements IElement {
  List<IElement> getChildren();
}
