import 'dart:collection';
import 'package:dpdf/src/kernel/geom/affine_transform.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/layout/font/font_provider.dart';
import 'package:dpdf/src/styledxmlparser/resolver/resource/resource_resolver.dart';
import 'package:dpdf/src/svg/css/svg_css_context.dart';
import 'package:dpdf/src/svg/exceptions/svg_exception_message_constant.dart';
import 'package:dpdf/src/svg/exceptions/svg_processing_exception.dart';
import 'package:dpdf/src/svg/renderers/i_svg_node_renderer.dart';
import 'package:dpdf/src/svg/utils/svg_text_properties.dart';

/// The SvgDrawContext keeps a stack of PdfCanvas instances, which
/// represent all levels of XObjects that are added to the root canvas.
class SvgDrawContext {
  final Map<String, ISvgNodeRenderer> _namedObjects = {};
  final ListQueue<PdfCanvas> _canvases = ListQueue<PdfCanvas>();
  final ListQueue<Rectangle> _viewports = ListQueue<Rectangle>();
  final ListQueue<String> _useIds = ListQueue<String>();
  final ListQueue<String> _patternIds = ListQueue<String>();

  final ResourceResolver _resourceResolver;
  final FontProvider _fontProvider;

  SvgTextProperties _textProperties = SvgTextProperties();
  SvgCssContext _cssContext = SvgCssContext();
  AffineTransform? _rootTransform;
  AffineTransform _clippingElementTransform = AffineTransform();
  List<double> _textMove = [0.0, 0.0];
  List<double>? _relativePosition;
  Rectangle? _customViewport;

  SvgDrawContext(ResourceResolver? resourceResolver, FontProvider? fontProvider)
      : _resourceResolver = resourceResolver ?? ResourceResolver(null),
        _fontProvider = fontProvider ?? BasicFontProvider() {
    _cssContext = SvgCssContext();
  }

  Rectangle? getCustomViewport() => _customViewport;
  void setCustomViewport(Rectangle? customViewport) =>
      _customViewport = customViewport;

  PdfCanvas getCurrentCanvas() => _canvases.first;
  PdfCanvas popCanvas() => _canvases.removeFirst();
  void pushCanvas(PdfCanvas canvas) => _canvases.addFirst(canvas);
  int size() => _canvases.length;

  void addViewPort(Rectangle viewPort) => _viewports.addFirst(viewPort);
  Rectangle? getCurrentViewPort() =>
      _viewports.isEmpty ? null : _viewports.first;
  Rectangle? getRootViewPort() => _viewports.isEmpty ? null : _viewports.last;
  void removeCurrentViewPort() {
    if (_viewports.isNotEmpty) _viewports.removeFirst();
  }

  void addNamedObject(String name, ISvgNodeRenderer namedObject) {
    if (name.isEmpty) {
      throw SvgProcessingException(
          SvgExceptionMessageConstant.NAMED_OBJECT_NAME_NULL_OR_EMPTY);
    }
    if (!_namedObjects.containsKey(name)) {
      _namedObjects[name] = namedObject;
    }
  }

  ISvgNodeRenderer? getNamedObject(String name) => _namedObjects[name];
  ResourceResolver getResourceResolver() => _resourceResolver;
  FontProvider getFontProvider() => _fontProvider;

  bool isIdUsedByUseTagBefore(String elementId) => _useIds.contains(elementId);
  void addUsedId(String elementId) => _useIds.addFirst(elementId);
  void removeUsedId(String elementId) => _useIds.removeFirst();

  AffineTransform getRootTransform() {
    _rootTransform ??= AffineTransform();
    return _rootTransform!;
  }

  void setRootTransform(AffineTransform newTransform) =>
      _rootTransform = newTransform;

  List<double> getTextMove() => _textMove;
  void resetTextMove() => _textMove = [0.0, 0.0];
  void addTextMove(double additionalMoveX, double additionalMoveY) {
    _textMove[0] += additionalMoveX;
    _textMove[1] += additionalMoveY;
  }

  AffineTransform getCurrentCanvasTransform() {
    return AffineTransform.copy(getCurrentCanvas().getGraphicsState().getCtm());
  }

  SvgCssContext getCssContext() => _cssContext;
  void setCssContext(SvgCssContext cssContext) => _cssContext = cssContext;

  bool pushPatternId(String patternId) {
    if (_patternIds.contains(patternId)) return false;
    _patternIds.addFirst(patternId);
    return true;
  }

  void popPatternId() => _patternIds.removeFirst();

  SvgTextProperties getSvgTextProperties() => _textProperties;
  void setSvgTextProperties(SvgTextProperties textProperties) =>
      _textProperties = textProperties;

  List<double>? getRelativePosition() => _relativePosition;
  void moveRelativePosition(double dx, double dy) {
    _relativePosition ??= [0.0, 0.0];
    _relativePosition![0] += dx;
    _relativePosition![1] += dy;
  }

  void resetRelativePosition() => _relativePosition = [0.0, 0.0];

  AffineTransform getClippingElementTransform() => _clippingElementTransform;
  void resetClippingElementTransform() =>
      _clippingElementTransform.setToIdentity();

  AffineTransform getConcatenatedTransform() {
    List<PdfCanvas> canvasList = [];
    int canvasesSize = size();
    for (int i = 0; i < canvasesSize; i++) {
      canvasList.add(popCanvas());
    }
    AffineTransform transform = AffineTransform();
    for (int i = canvasList.length - 1; i >= 0; i--) {
      PdfCanvas pdfCanvas = canvasList[i];
      final matrix = pdfCanvas.getGraphicsState().getCtm();
      transform.concatenate(matrix);
      pushCanvas(pdfCanvas);
    }
    return transform;
  }
}
