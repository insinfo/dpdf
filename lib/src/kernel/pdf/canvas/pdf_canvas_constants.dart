/// A container for constants defined in the PDF specification (ISO 32000-1).
class PdfCanvasConstants {
  PdfCanvasConstants._();
}

/// The text rendering mode determines whether showing text causes glyph
/// outlines to be stroked, filled, used as a clipping boundary, or some
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

/// The line cap style specifies the shape to be used at the ends of open
/// subpaths (and dashes, if any) when they are stroked.
class LineCapStyle {
  LineCapStyle._();

  /// The stroke is squared of at the endpoint of the path.
  static const int BUTT = 0;

  /// A semicircular arc with a diameter equal to the line width is drawn
  /// around the endpoint and filled in.
  static const int ROUND = 1;

  /// The stroke continues beyond the endpoint of the path for a distance
  /// equal to half the line width and is squared off.
  static const int PROJECTING_SQUARE = 2;
}

/// The line join style specifies the shape to be used at the corners of
/// paths that are stroked.
class LineJoinStyle {
  LineJoinStyle._();

  /// The outer edges of the strokes for the two segments are extended
  /// until they meet at an angle, as in a picture frame.
  static const int MITER = 0;

  /// An arc of a circle with a diameter equal to the line width is drawn
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
