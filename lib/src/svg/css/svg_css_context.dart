import 'package:dpdf/src/styledxmlparser/css/resolve/abstract_css_context.dart';

class SvgCssContext extends AbstractCssContext {
  double _rootFontSize = 12.0;

  @override
  double getRootFontSize() => _rootFontSize;

  @override
  void setRootFontSize(double fontSize) {
    _rootFontSize = fontSize;
  }
}
