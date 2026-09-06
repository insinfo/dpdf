/// Container for CSS context properties that influence CSS resolution.
abstract class AbstractCssContext {
  int _quotesDepth = 0;

  /// Gets the quotes depth.
  int getQuotesDepth() => _quotesDepth;

  /// Sets the quotes depth.
  void setQuotesDepth(int quotesDepth) {
    _quotesDepth = quotesDepth;
  }

  /// Gets the root font size.
  double getRootFontSize();

  /// Sets the root font size.
  void setRootFontSize(double fontSize);
}
