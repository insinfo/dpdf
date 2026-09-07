/// Numeric constants for PDF graphics operations.
class PdfCanvasConstants {
  PdfCanvasConstants._();
}

/// Text rendering selects whether glyph outlines are
/// filled, stroked, incorporated into clipping, or a
/// combination of the three.
class TextRenderingMode {
  TextRenderingMode._();

  /// Fill text
  static const int FILL = 0;

  /// Stroke text, providing the outline of the glyphs
  static const int STROKE = 1;

  /// Fill and stroke text
  static const int FILL_STROKE = 2;

  /// Neither fill nor stroke, i.e. render invisibly
  static const int INVISIBLE = 3;

  /// Fill text and add to path for clipping
  static const int FILL_CLIP = 4;

  /// Stroke text and add to path for clipping
  static const int STROKE_CLIP = 5;

  /// Fill, then stroke text and add to path for clipping
  static const int FILL_STROKE_CLIP = 6;

  /// Add text to path for clipping
  static const int CLIP = 7;
}

/// Stroke caps control the terminal shape of open
/// subpaths (and dashes, if any) when they are stroked.
class LineCapStyle {
  LineCapStyle._();

  /// The stroke is squared of at the endpoint of the path.
  static const int BUTT = 0;

  /// A half-circle matching the stroke width is placed
  /// around the endpoint and filled in.
  static const int ROUND = 1;

  /// The stroke extends beyond its endpoint by
  /// equal to half the line width and is squared off.
  static const int PROJECTING_SQUARE = 2;
}

/// Stroke joins control the junction between segments of
/// paths that are stroked.
class LineJoinStyle {
  LineJoinStyle._();

  /// The outside stroke edges of adjacent segments continue
  /// until they meet at an angle, as in a picture frame.
  static const int MITER = 0;

  /// A circular arc matching the stroke width is placed
  /// around the point where the two segments meet.
  static const int ROUND = 1;

  /// The two segments are finished with butt caps.
  static const int BEVEL = 2;
}

/// Rule for determining which points lie inside a path.
class FillingRule {
  FillingRule._();

  /// The nonzero winding number rule.
  static const int NONZERO_WINDING = 1;

  /// The even-odd winding number rule.
  static const int EVEN_ODD = 2;
}
