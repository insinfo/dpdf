/// A class containing constant values signifying the property names of tags, attribute, CSS-style
/// and certain values in SVG XML.
class SvgConstants {
  SvgConstants._();

  /// Class containing the constant property names for the tags in the SVG spec
  static get Tags => SvgTags;

  static get Attributes => SvgAttributes;

  static get Values => SvgValues;
}

/// Class containing the constant property names for the tags in the SVG spec
class SvgTags {
  SvgTags._();

  /// Tag defining a Hyperlink.
  static const String A = "a";

  /// Alternate glyphs to be used instead of regular grlyphs, e.g. ligatures, Asian scripts, ...
  static const String ALT_GLYPH = "altGlyph";

  /// Defines a set of glyph substitions.
  static const String ALT_GLYPH_DEF = "altGlyphDef";

  /// Defines a candidate set of glyph substitutions.
  static const String ALT_GLYPH_ITEM = "altGlyphItem";

  /// Not supported in PDF.
  static const String ANIMATE = "animate";

  /// Not supported in PDF.
  static const String ANIMATE_MOTION = "animateMotion";

  /// Not supported in PDF.
  static const String ANIMATE_COLOR = "animateColor";

  /// Not supported in PDF.
  static const String ANIMATE_TRANSFORM = "animateTransform";

  /// Tag defining a circle.
  static const String CIRCLE = "circle";

  /// Tag defining a clipping path.
  static const String CLIP_PATH = "clipPath";

  /// Tag defining the color profile to be used.
  static const String COLOR_PROFILE = "color-profile";

  /// Not supported in PDF
  static const String CURSOR = "cursor";

  /// Tag defining objects that can be reused from another context
  static const String DEFS = "defs";

  /// Tag defining the description of its parent element
  static const String DESC = "desc";

  /// Tag defining an ellipse.
  static const String ELLIPSE = "ellipse";

  /// Tag defining how to blend two objects together.
  static const String FE_BLEND = "feBlend";

  /// Tag defining the color matrix transformations that can be performed.
  static const String FE_COLOR_MATRIX = "feColorMatrix";

  /// Tag defining color component remapping.
  static const String FE_COMPONENT_TRANSFER = "feComponentTransfer";

  /// Tag defining the combination of two input images.
  static const String FE_COMPOSITE = "feComposite";

  /// Tag defining a matrix convolution filter
  static const String FE_COMVOLVE_MATRIX = "feConvolveMatrix";

  /// Tag defining the lighting map.
  static const String FE_DIFFUSE_LIGHTING = "feDiffuseLighting";

  /// Tag defining the values to displace an image.
  static const String FE_DISPLACEMENT_MAP = "feDisplacementMap";

  /// Tag defining a distant light source.
  static const String FE_DISTANT_LIGHT = "feDistantLight";

  /// Tag defining the fill of a subregion.
  static const String FE_FLOOD = "feFlood";

  /// Tag defining the transfer function for the Alpha component.
  static const String FE_FUNC_A = "feFuncA";

  /// Tag defining the transfer function for the Blue component.
  static const String FE_FUNC_B = "feFuncB";

  /// Tag defining the transfer function for the Green component.
  static const String FE_FUNC_G = "feFuncG";

  /// Tag defining the transfer function for the Red component.
  static const String FE_FUNC_R = "feFuncR";

  /// Tag defining the blur values.
  static const String FE_GAUSSIAN_BLUR = "feGaussianBlur";

  /// Tag defining a image data from a source.
  static const String FE_IMAGE = "feImage";

  /// Tag defining that filters will be applied concurrently instead of sequentially.
  static const String FE_MERGE = "feMerge";

  /// Tag defining a node in a merge.
  static const String FE_MERGE_NODE = "feMergeNode";

  /// Tag defining the erosion or dilation of an image.
  static const String FE_MORPHOLOGY = "feMorphology";

  /// Tag defining the offset of an image.
  static const String FE_OFFSET = "feOffset";

  /// Tag defining a point light effect.
  static const String FE_POINT_LIGHT = "fePointLight";

  /// Tag defining a lighting map.
  static const String FE_SPECULAR_LIGHTING = "feSpecularLighting";

  /// Tag defining a spotlight.
  static const String FE_SPOTLIGHT = "feSpotLight";

  /// Tag defining a fill that can be repeated.
  static const String FE_TILE = "feTile";

  /// Tag defining values for the perlin turbulence function.
  static const String FE_TURBULENCE = "feTurbulence";

  /// Tag defining a collection of filter operations.
  static const String FILTER = "filter";

  /// Tag defining a font.
  static const String FONT = "font";

  /// Tag defining a font-face.
  static const String FONT_FACE = "font-face";

  /// Tag defining the formats of the font.
  static const String FONT_FACE_FORMAT = "font-face-format";

  /// Tag defining the name of the font.
  static const String FONT_FACE_NAME = "font-face-name";

  /// Tag defining the source file of the font.
  static const String FONT_FACE_SRC = "font-face-src";

  /// Tag defining the URI of a font.
  static const String FONT_FACE_URI = "font-face-uri";

  /// Tag definign a foreign XML standard to be inserted.
  static const String FOREIGN_OBJECT = "foreignObject";

  /// Tag defining a group of elements.
  static const String G = "g";

  /// Tag defining a single glyph.
  static const String GLYPH = "glyph";

  /// Tag defining a sigle glyph for altGlyph.
  static const String GLYPH_REF = "glyphRef";

  /// Tag defining the horizontal kerning values in between two glyphs.
  static const String HKERN = "hkern";

  /// Tag defining an image.
  static const String IMAGE = "image";

  /// Tag defining a line.
  static const String LINE = "line";

  /// Tag defining a linear gradient.
  static const String LINEAR_GRADIENT = "linearGradient";

  /// Tag defining a link
  static const String LINK = "link";

  /// Tag defining the graphics (arrowheads or polymarkers) to be drawn at the end of paths, lines, etc.
  static const String MARKER = "marker";

  /// Tag defining a mask.
  static const String MASK = "mask";

  /// Tag defining metadata.
  static const String METADATA = "metadata";

  /// Tag defining content to be rendered if a glyph is missing from the font.
  static const String MISSING_GLYPH = "missing-glyph";

  /// Not supported in PDF
  static const String MPATH = "mpath";

  /// Tag defining a path.
  static const String PATH = "path";

  /// Tag defining a graphical object that can be repeated.
  static const String PATTERN = "pattern";

  /// Tag defining a polygon shape.
  static const String POLYGON = "polygon";

  /// Tag defining a polyline shape.
  static const String POLYLINE = "polyline";

  /// Tag defining a radial gradient
  static const String RADIAL_GRADIENT = "radialGradient";

  /// Tag defining a rectangle.
  static const String RECT = "rect";

  /// Not supported in PDF.
  static const String SCRIPT = "script";

  /// Not supported in PDF.
  static const String SET = "set";

  /// Tag defining the ramp of colors in a gradient.
  static const String STOP = "stop";

  /// Tag defining the color in stop point of a gradient.
  static const String STOP_COLOR = "stop-color";

  /// Tag defining the opacity in stop point of a gradient.
  static const String STOP_OPACITY = "stop-opacity";

  /// Tag defining the style to be.
  static const String STYLE = "style";

  /// Tag defining an SVG element.
  static const String SVG = "svg";

  /// Tag defining a switch element.
  static const String SWITCH = "switch";

  /// Tag defining graphical templates that can be reused by the use tag.
  static const String SYMBOL = "symbol";

  /// Tag defining text to be drawn on a page/screen.
  static const String TEXT = "text";

  /// Phantom tag for text leaf.
  static const String TEXT_LEAF = ":text-leaf";

  /// Tag defining a path on which text can be drawn.
  static const String TEXT_PATH = "textPath";

  /// Tag defining the description of an element.
  static const String TITLE = "title";

  /// Tag defining a span within a text element.
  static const String TSPAN = "tspan";

  /// Tag defining the use of a named object.
  static const String USE = "use";

  /// Tag defining how to view the image.
  static const String VIEW = "view";

  /// Tag defining the vertical kerning values in between two glyphs.
  static const String VKERN = "vkern";

  /// Tag defining the xml stylesheet declaration.
  static const String XML_STYLESHEET = "xml-stylesheet";
}

/// Class containing the constant property names for the attributes of tags in the SVG spec
class SvgAttributes {
  SvgAttributes._();

  /// Attribute defining the clipping path to be applied to a specific shape or group of shapes.
  static const String CLIP_PATH = "clip-path";

  /// Attribute defining the clipping rule in a clipping path (or element thereof).
  static const String CLIP_RULE = "clip-rule";

  /// Attribute defining the x value of the center of a circle or ellipse.
  static const String CX = "cx";

  /// Attribute defining the y value of the center of a circle or ellipse.
  static const String CY = "cy";

  /// Attribute defining the outline of a shape.
  static const String D = "d";

  /// Attribute defining the direction used by the text
  static const String DIRECTION = "direction";

  /// Attribute defining the relative x-translation of a text-element
  static const String DX = "dx";

  /// Attribute defining the relative y-translation of a text-element
  static const String DY = "dy";

  /// Attribute defining the fill color.
  static const String FILL = "fill";

  /// Attribute defining the fill opacity.
  static const String FILL_OPACITY = "fill-opacity";

  /// Attribute defining the fill rule.
  static const String FILL_RULE = "fill-rule";

  /// Attribute defining the font family.
  static const String FONT_FAMILY = "font-family";

  /// Attribute defining the font weight.
  static const String FONT_WEIGHT = "font-weight";

  /// Attribute defining the font style.
  static const String FONT_STYLE = "font-style";

  /// Attribute defining the font size.
  static const String FONT_SIZE = "font-size";

  /// The Constant ITALIC.
  static const String ITALIC = "italic";

  /// The Constant BOLD.
  static const String BOLD = "bold";

  /// Attribute defining the units relation for a color gradient.
  static const String GRADIENT_UNITS = "gradientUnits";

  /// Attribute defining the transformations for a color gradient.
  static const String GRADIENT_TRANSFORM = "gradientTransform";

  /// Attribute defining the height.
  static const String HEIGHT = "height";

  /// Attribute defining the href value.
  static const String HREF = "href";

  /// Attribute defining the unique id of an element.
  static const String ID = "id";

  /// Attribute defining the marker to use at the end of a path, line, polygon or polyline
  static const String MARKER_END = "marker-end";

  /// Attribute defining the height of the viewport in which the marker is to be fitted
  static const String MARKER_HEIGHT = "markerHeight";

  /// Attribute defining shorthand for marker-start/marker-mid/marker-end
  static const String MARKER = "marker";

  /// Attribute defining the marker drawn at every other vertex but the start and end of a path, line, polygon or polyline
  static const String MARKER_MID = "marker-mid";

  /// Attribute defining the marker to use at the start of a path, line, polygon or polyline
  static const String MARKER_START = "marker-start";

  /// Attribute defining the width of the viewport in which the marker is to be fitted
  static const String MARKER_WIDTH = "markerWidth";

  /// Attribute defining the coordinate system for attributes ‘markerWidth’, ‘markerHeight’ and the contents of the ‘marker’.
  static const String MARKER_UNITS = "markerUnits";

  /// Attribute defining the offset of a stop color for gradients.
  static const String OFFSET = "offset";

  /// Attribute defining the opacity of a group or graphic element.
  static const String OPACITY = "opacity";

  /// Attribute defining the orientation of a marker
  static const String ORIENT = "orient";

  /// Close Path Operator.
  static const String PATH_DATA_CLOSE_PATH = "Z";

  /// CurveTo Path Operator.
  static const String PATH_DATA_CURVE_TO = "C";

  /// Relative CurveTo Path Operator.
  static const String PATH_DATA_REL_CURVE_TO = "c";

  /// Attribute defining Elliptical arc path operator.
  static const String PATH_DATA_ELLIPTICAL_ARC_A = "A";

  /// Attribute defining Elliptical arc path operator.
  static const String PATH_DATA_REL_ELLIPTICAL_ARC_A = "a";

  /// Smooth CurveTo Path Operator.
  static const String PATH_DATA_CURVE_TO_S = "S";

  /// Relative Smooth CurveTo Path Operator.
  static const String PATH_DATA_REL_CURVE_TO_S = "s";

  /// Absolute LineTo Path Operator.
  static const String PATH_DATA_LINE_TO = "L";

  /// Absolute hrizontal LineTo Path Operator.
  static const String PATH_DATA_LINE_TO_H = "H";

  /// Relative horizontal LineTo Path Operator.
  static const String PATH_DATA_REL_LINE_TO_H = "h";

  /// Absolute vertical LineTo Path operator.
  static const String PATH_DATA_LINE_TO_V = "V";

  /// Relative vertical LineTo Path operator.
  static const String PATH_DATA_REL_LINE_TO_V = "v";

  /// Relative LineTo Path Operator.
  static const String PATH_DATA_REL_LINE_TO = "l";

  /// MoveTo Path Operator.
  static const String PATH_DATA_MOVE_TO = "M";

  /// Relative MoveTo Path Operator.
  static const String PATH_DATA_REL_MOVE_TO = "m";

  /// Shorthand/smooth quadratic Bézier curveto.
  static const String PATH_DATA_SHORTHAND_CURVE_TO = "T";

  /// Relative Shorthand/smooth quadratic Bézier curveto.
  static const String PATH_DATA_REL_SHORTHAND_CURVE_TO = "t";

  /// Catmull-Rom curve command.
  static const String PATH_DATA_CATMULL_CURVE = "R";

  /// Relative Catmull-Rom curve command.
  static const String PATH_DATA_REL_CATMULL_CURVE = "r";

  /// Bearing command.
  static const String PATH_DATA_BEARING = "B";

  /// Relative Bearing command.
  static const String PATH_DATA_REL_BEARING = "b";

  /// Quadratic CurveTo Path Operator.
  static const String PATH_DATA_QUAD_CURVE_TO = "Q";

  /// Relative Quadratic CurveTo Path Operator.
  static const String PATH_DATA_REL_QUAD_CURVE_TO = "q";

  /// Attribute defining the coordinate system for the pattern content.
  static const String PATTERN_CONTENT_UNITS = "patternContentUnits";

  /// Attribute defining list of transform definitions for the pattern element.
  static const String PATTERN_TRANSFORM = "patternTransform";

  /// Attribute defining the coordinate system for attributes x, y, width , and height in pattern.
  static const String PATTERN_UNITS = "patternUnits";

  /// Attribute defining the points of a polyline or polygon.
  static const String POINTS = "points";

  /// Attribute defining how to preserve the aspect ratio when scaling.
  static const String PRESERVE_ASPECT_RATIO = "preserveAspectRatio";

  /// Attribute defining the radius of a circle.
  static const String R = "r";

  /// Attribute defining the x-axis coordinate of the reference point which is to be aligned exactly at the marker position.
  static const String REFX = "refX";

  /// Attribute defining the y-axis coordinate of the reference point which is to be aligned exactly at the marker position.
  static const String REFY = "refY";

  /// Attribute defining the x-axis of an ellipse or the x-axis radius of rounded rectangles.
  static const String RX = "rx";

  /// Attribute defining the y-axis of an ellipse or the y-axis radius of rounded rectangles.
  static const String RY = "ry";

  /// Attribute defining the spread method for a color gradient.
  static const String SPREAD_METHOD = "spreadMethod";

  /// Attribute defining the stroke color.
  static const String STROKE = "stroke";

  /// Attribute defining the stroke dash offset.
  static const String STROKE_DASHARRAY = "stroke-dasharray";

  /// Attribute defining the stroke dash offset.
  static const String STROKE_DASHOFFSET = "stroke-dashoffset";

  /// Attribute defining the stroke linecap.
  static const String STROKE_LINECAP = "stroke-linecap";

  /// Attribute defining the stroke linejoin.
  static const String STROKE_LINEJOIN = "stroke-linejoin";

  /// Attribute defining the stroke miterlimit.
  static const String STROKE_MITERLIMIT = "stroke-miterlimit";

  /// Attribute defingin the stroke opacity.
  static const String STROKE_OPACITY = "stroke-opacity";

  /// Attribute defining the stroke width.
  static const String STROKE_WIDTH = "stroke-width";

  /// Attribute defining the style of an element.
  static const String STYLE = "style";

  /// Attribute defining the text content of a text node.
  static const String TEXT_CONTENT = "text_content";

  /// Attribute defining the text anchor used by the text
  static const String TEXT_ANCHOR = "text-anchor";

  /// Attribute defining a transformation that needs to be applied.
  static const String TRANSFORM = "transform";

  /// Attribute defining the viewbox of an element.
  static const String VIEWBOX = "viewBox";

  /// Attribute defining the width of an element.
  static const String WIDTH = "width";

  /// Attribute defining the x value of an element.
  static const String X = "x";

  /// Attribute defining the first x coordinate value of a line.
  static const String X1 = "x1";

  /// Attribute defining the second x coordinate value of a line.
  static const String X2 = "x2";

  /// Attribute defining image source.
  static const String XLINK_HREF = "xlink:href";

  /// Attribute defining XML namespace
  static const String XMLNS = "xmlns";

  /// Attribute defining the property that sets how white space inside an element is handled.
  static const String XML_SPACE = "xml:space";

  /// Attribute defining the y value of an element.
  static const String Y = "y";

  /// Attribute defining the first y coordinate value of a line.
  static const String Y1 = "y1";

  /// Attribute defining the second y coordinate value of a line.
  static const String Y2 = "y2";

  /// Attribute defining vector-effect.
  static const String VECTOR_EFFECT = "vector-effect";

  /// Attribute defining version.
  static const String VERSION = "version";
}

/// Class containing the constants for values appearing in SVG tags and attributes
class SvgValues {
  SvgValues._();

  /// Value representing automatic orientation for the marker attribute orient.
  static const String AUTO = "auto";

  /// Value representing reverse automatic orientation for the start marker.
  static const String AUTO_START_REVERSE = "auto-start-reverse";

  /// Value representing the default value for the stroke linecap.
  static const String BUTT = "butt";

  /// Value representing the default aspect ratio: xmidymid.
  static const String DEFAULT_ASPECT_RATIO = SvgValues.XMID_YMID;

  /// Default svg view port width value (300px * 0.75 = 225).
  static const double DEFAULT_VIEWPORT_WIDTH = 225.0;

  /// Default svg view port height value (150px * 0.75 = 112.5).
  static const double DEFAULT_VIEWPORT_HEIGHT = 112.5;

  /// Default width and height value.
  static const String DEFAULT_WIDTH_AND_HEIGHT_VALUE = "100%";

  /// Value representing how to preserve the aspect ratio when dealing with images.
  static const String DEFER = "defer";

  /// Value representing the fill rule "even odd".
  static const String FILL_RULE_EVEN_ODD = "evenodd";

  /// Value representing the fill rule "nonzero".
  static const String FILL_RULE_NONZERO = "nonzero";

  /// Value representing the meet for preserve aspect ratio calculations.
  static const String MEET = "meet";

  /// Value representing the "none" value.
  static const String NONE = "none";

  /// Value representing the "non-scaling-stroke" value for vector-effect attribute.
  static const String NONE_SCALING_STROKE = "non-scaling-stroke";

  /// Value representing the units relation "objectBoundingBox".
  static const String OBJECT_BOUNDING_BOX = "objectBoundingBox";

  /// The value representing slice for the preserve aspect ratio calculations;
  static const String SLICE = "slice";

  /// Value representing the text-alignment end for text objects
  static const String TEXT_ANCHOR_END = "end";

  /// Value representing the text-alignment middle for text objects
  static const String TEXT_ANCHOR_MIDDLE = "middle";

  /// Value representing the text-alignment start for text objects
  static const String TEXT_ANCHOR_START = "start";

  /// Value representing the gradient spread method "pad".
  static const String SPREAD_METHOD_PAD = "pad";

  /// Value representing the gradient spread method "repeat".
  static const String SPREAD_METHOD_REPEAT = "repeat";

  /// Value representing the gradient spread method "reflect".
  static const String SPREAD_METHOD_REFLECT = "reflect";

  /// The value for markerUnits that represent values in a coordinate system which has a single unit equal the size in user units of the current stroke width.
  static const String STROKEWIDTH = "strokeWidth";

  /// Value representing the units relation "userSpaceOnUse".
  static const String USER_SPACE_ON_USE = "userSpaceOnUse";

  /// The number of viewBox values.
  static const int VIEWBOX_VALUES_NUMBER = 4;

  /// Value representing how to align when scaling.
  static const String XMIN_YMIN = "xminymin";

  /// Value representing how to align when scaling.
  static const String XMIN_YMID = "xminymid";

  /// Value representing how to align when scaling.
  static const String XMIN_YMAX = "xminymax";

  /// Value representing how to align when scaling.
  static const String XMID_YMID = "xmidymid";

  /// Value representing how to align when scaling.
  static const String XMID_YMIN = "xmidymin";

  /// Value representing how to align when scaling.
  static const String XMID_YMAX = "xmidymax";

  /// Value representing how to align when scaling.
  static const String XMAX_YMIN = "xmaxymin";

  /// Value representing how to align when scaling.
  static const String XMAX_YMID = "xmaxymid";

  /// Value representing how to align when scaling.
  static const String XMAX_YMAX = "xmaxymax";

  @deprecated
  static const String VERSION1_1 = "1.1";
}
