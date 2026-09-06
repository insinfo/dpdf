/// A class containing constant values signifying the property names of tags, attribute, CSS-style
/// and certain values in SVG XML.
class CraftSvgConstants {
  CraftSvgConstants._();

  /// Names of SVG elements.
  static get Tags => SvgTags;

  static get Attributes => SvgAttributes;

  static get Values => SvgValues;
}

/// Names of SVG elements.
class SvgTags {
  SvgTags._();

  /// Tag defining a Hyperlink.
  static const String A = "a";

  /// Alternative glyph selection, including ligatures and script variants.
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

  /// Reusable SVG object definitions.
  static const String DEFS = "defs";

  /// Tag defining the description of its parent element
  static const String DESC = "desc";

  /// Tag defining an ellipse.
  static const String ELLIPSE = "ellipse";

  /// Tag defining how to blend two objects together.
  static const String FE_BLEND = "feBlend";

  /// Color-matrix filter operation.
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

  /// Transfer function for alpha values.
  static const String FE_FUNC_A = "feFuncA";

  /// Transfer function for blue values.
  static const String FE_FUNC_B = "feFuncB";

  /// Transfer function for green values.
  static const String FE_FUNC_G = "feFuncG";

  /// Transfer function for red values.
  static const String FE_FUNC_R = "feFuncR";

  /// Tag defining the blur values.
  static const String FE_GAUSSIAN_BLUR = "feGaussianBlur";

  /// Tag defining a image data from a source.
  static const String FE_IMAGE = "feImage";

  /// Combines filter outputs in parallel.
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

  /// Horizontal adjustment between glyph pairs.
  static const String HKERN = "hkern";

  /// Tag defining an image.
  static const String IMAGE = "image";

  /// Tag defining a line.
  static const String LINE = "line";

  /// Tag defining a linear gradient.
  static const String LINEAR_GRADIENT = "linearGradient";

  /// Tag defining a link
  static const String LINK = "link";

  /// Marker graphics attached to path vertices.
  static const String MARKER = "marker";

  /// Tag defining a mask.
  static const String MASK = "mask";

  /// Tag defining metadata.
  static const String METADATA = "metadata";

  /// Fallback content for unavailable glyphs.
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

  /// Reusable symbol definition referenced by a use element.
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

  /// Vertical adjustment between glyph pairs.
  static const String VKERN = "vkern";

  /// Tag defining the xml stylesheet declaration.
  static const String XML_STYLESHEET = "xml-stylesheet";
}

/// Names of SVG attributes.
class SvgAttributes {
  SvgAttributes._();

  /// Clipping-path reference for a shape or group.
  static const String CLIP_PATH = "clip-path";

  /// Interior rule used by a clipping path.
  static const String CLIP_RULE = "clip-rule";

  /// Horizontal coordinate of a circle or ellipse center.
  static const String CX = "cx";

  /// Vertical coordinate of a circle or ellipse center.
  static const String CY = "cy";

  /// Attribute defining the outline of a shape.
  static const String D = "d";

  /// Attribute defining the direction used by the text
  static const String DIRECTION = "direction";

  /// Horizontal displacement of positioned text.
  static const String DX = "dx";

  /// Vertical displacement of positioned text.
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

  /// Coordinate units for gradient geometry.
  static const String GRADIENT_UNITS = "gradientUnits";

  /// Attribute defining the transformations for a color gradient.
  static const String GRADIENT_TRANSFORM = "gradientTransform";

  /// Attribute defining the height.
  static const String HEIGHT = "height";

  /// Attribute defining the href value.
  static const String HREF = "href";

  /// Attribute defining the unique id of an element.
  static const String ID = "id";

  /// Marker assigned to the final path vertex.
  static const String MARKER_END = "marker-end";

  /// Height of the marker viewport.
  static const String MARKER_HEIGHT = "markerHeight";

  /// Attribute defining shorthand for marker-start/marker-mid/marker-end
  static const String MARKER = "marker";

  /// Marker assigned to internal path vertices.
  static const String MARKER_MID = "marker-mid";

  /// Marker assigned to the initial path vertex.
  static const String MARKER_START = "marker-start";

  /// Width of the marker viewport.
  static const String MARKER_WIDTH = "markerWidth";

  /// Units used for marker geometry and its viewport dimensions.
  static const String MARKER_UNITS = "markerUnits";

  /// Location of a gradient color stop.
  static const String OFFSET = "offset";

  /// Opacity of an element or group.
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

  /// Units used inside the pattern definition.
  static const String PATTERN_CONTENT_UNITS = "patternContentUnits";

  /// Transformations applied to a pattern.
  static const String PATTERN_TRANSFORM = "patternTransform";

  /// Units for pattern position and dimensions.
  static const String PATTERN_UNITS = "patternUnits";

  /// Attribute defining the points of a polyline or polygon.
  static const String POINTS = "points";

  /// Aspect-ratio handling during scaling.
  static const String PRESERVE_ASPECT_RATIO = "preserveAspectRatio";

  /// Attribute defining the radius of a circle.
  static const String R = "r";

  /// Horizontal marker reference coordinate.
  static const String REFX = "refX";

  /// Vertical marker reference coordinate.
  static const String REFY = "refY";

  /// Horizontal radius for an ellipse or rounded corner.
  static const String RX = "rx";

  /// Vertical radius for an ellipse or rounded corner.
  static const String RY = "ry";

  /// Gradient behavior outside its stop interval.
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

  /// Transformation applied to the element.
  static const String TRANSFORM = "transform";

  /// Attribute defining the viewbox of an element.
  static const String VIEWBOX = "viewBox";

  /// Attribute defining the width of an element.
  static const String WIDTH = "width";

  /// Attribute defining the x value of an element.
  static const String X = "x";

  /// Horizontal coordinate of the line's initial endpoint.
  static const String X1 = "x1";

  /// Horizontal coordinate of the line's final endpoint.
  static const String X2 = "x2";

  /// Attribute defining image source.
  static const String XLINK_HREF = "xlink:href";

  /// Attribute defining XML namespace
  static const String XMLNS = "xmlns";

  /// Attribute defining the property that sets how white space inside an element is handled.
  static const String XML_SPACE = "xml:space";

  /// Attribute defining the y value of an element.
  static const String Y = "y";

  /// Vertical coordinate of the line's initial endpoint.
  static const String Y1 = "y1";

  /// Vertical coordinate of the line's final endpoint.
  static const String Y2 = "y2";

  /// Attribute defining vector-effect.
  static const String VECTOR_EFFECT = "vector-effect";

  /// Attribute defining version.
  static const String VERSION = "version";
}

/// Standard values used by SVG attributes and elements.
class SvgValues {
  SvgValues._();

  /// Automatic marker orientation.
  static const String AUTO = "auto";

  /// Automatic orientation with reversal at the initial vertex.
  static const String AUTO_START_REVERSE = "auto-start-reverse";

  /// Default stroke cap value.
  static const String BUTT = "butt";

  /// Value representing the default aspect ratio: xmidymid.
  static const String DEFAULT_ASPECT_RATIO = SvgValues.XMID_YMID;

  /// Default svg view port width value (300px * 0.75 = 225).
  static const double DEFAULT_VIEWPORT_WIDTH = 225.0;

  /// Default svg view port height value (150px * 0.75 = 112.5).
  static const double DEFAULT_VIEWPORT_HEIGHT = 112.5;

  /// Default width and height value.
  static const String DEFAULT_WIDTH_AND_HEIGHT_VALUE = "100%";

  /// Aspect-ratio handling for image placement.
  static const String DEFER = "defer";

  /// Value representing the fill rule "even odd".
  static const String FILL_RULE_EVEN_ODD = "evenodd";

  /// Value representing the fill rule "nonzero".
  static const String FILL_RULE_NONZERO = "nonzero";

  /// Fits the entire source within the destination bounds.
  static const String MEET = "meet";

  /// Value representing the "none" value.
  static const String NONE = "none";

  /// Value representing the "non-scaling-stroke" value for vector-effect attribute.
  static const String NONE_SCALING_STROKE = "non-scaling-stroke";

  /// Value representing the units relation "objectBoundingBox".
  static const String OBJECT_BOUNDING_BOX = "objectBoundingBox";

  /// Scales to cover the destination bounds;
  static const String SLICE = "slice";

  /// Text anchored at its end.
  static const String TEXT_ANCHOR_END = "end";

  /// Text anchored at its midpoint.
  static const String TEXT_ANCHOR_MIDDLE = "middle";

  /// Text anchored at its start.
  static const String TEXT_ANCHOR_START = "start";

  /// Value representing the gradient spread method "pad".
  static const String SPREAD_METHOD_PAD = "pad";

  /// Value representing the gradient spread method "repeat".
  static const String SPREAD_METHOD_REPEAT = "repeat";

  /// Value representing the gradient spread method "reflect".
  static const String SPREAD_METHOD_REFLECT = "reflect";

  /// Marker units expressed as multiples of the current stroke width.
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
