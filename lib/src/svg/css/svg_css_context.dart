import 'package:pdfcraft/src/styledxmlparser/css/resolve/abstract_css_context.dart';

class CraftSvgCssContext extends CraftAbstractCssContext {
  double _rootFontSize = 12.0;

  @override
  double getRootFontSize() => _rootFontSize;

  @override
  void setRootFontSize(double fontSize) {
    _rootFontSize = fontSize;
  }
}
