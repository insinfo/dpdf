/// Types of events that can occur during content stream parsing.
enum EventType {
  /// Invoked when a text block is entered.
  beginTextBlock,

  /// Invoked when a text block is exited.
  endTextBlock,

  /// Invoked when text is rendered.
  renderText,

  /// Invoked when a path is rendered.
  renderPath,

  /// Invoked when an image is rendered.
  renderImage,

  /// Invoked when a marked content sequence begins.
  beginMarkedContent,

  /// Invoked when a marked content sequence ends.
  endMarkedContent,

  /// Invoked when the clipping path is changed.
  clipPathChanged
}
