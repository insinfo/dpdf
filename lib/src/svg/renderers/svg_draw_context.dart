import 'dart:collection';
import 'package:dpdf/src/kernel/geom/affine_transform.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/layout/font/font_provider.dart';
import 'package:dpdf/src/styledxmlparser/resolver/resource/resource_resolver.dart';
import 'package:dpdf/src/svg/css/svg_css_context.dart';
import 'package:dpdf/src/svg/exceptions/svg_exception_message_constant.dart';
import 'package:dpdf/src/svg/exceptions/svg_processing_exception.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/utils/svg_text_properties.dart';

/// The SvgDrawContext keeps a stack of PdfCanvas instances, which
/// track the nested XObjects associated with the root canvas.
class CraftSvgDrawContext {
  final Map<String, CraftSvgNodeRenderer> _namedObjects = {};
  final ListQueue<CraftPdfCanvas> _canvases = ListQueue<CraftPdfCanvas>();
  final ListQueue<CraftRectangle> _viewports = ListQueue<CraftRectangle>();
  final ListQueue<String> _useIds = ListQueue<String>();
  final ListQueue<String> _patternIds = ListQueue<String>();

  final CraftResourceResolver _resourceResolver;
  final CraftFontProvider _fontProvider;

  SvgTextProperties _textProperties = SvgTextProperties();
  CraftSvgCssContext _cssContext = CraftSvgCssContext();
  CraftAffineTransform? _rootTransform;
  CraftAffineTransform _clippingElementTransform = CraftAffineTransform();
  List<double> _textMove = [0.0, 0.0];
  List<double>? _relativePosition;
  CraftRectangle? _customViewport;

  CraftSvgDrawContext(
      CraftResourceResolver? resourceResolver, CraftFontProvider? fontProvider)
      : _resourceResolver = resourceResolver ?? CraftResourceResolver(null),
        _fontProvider = fontProvider ?? CraftBasicFontProvider() {
    _cssContext = CraftSvgCssContext();
  }

  CraftRectangle? getCustomViewport() => _customViewport;
  void setCustomViewport(CraftRectangle? customViewport) =>
      _customViewport = customViewport;

  CraftPdfCanvas getCurrentCanvas() => _canvases.first;
  CraftPdfCanvas popCanvas() => _canvases.removeFirst();
  void pushCanvas(CraftPdfCanvas canvas) => _canvases.addFirst(canvas);
  int size() => _canvases.length;

  void addViewPort(CraftRectangle viewPort) => _viewports.addFirst(viewPort);
  CraftRectangle? getCurrentViewPort() =>
      _viewports.isEmpty ? null : _viewports.first;
  CraftRectangle? getRootViewPort() =>
      _viewports.isEmpty ? null : _viewports.last;
  void removeCurrentViewPort() {
    if (_viewports.isNotEmpty) _viewports.removeFirst();
  }

  void addNamedObject(String name, CraftSvgNodeRenderer namedObject) {
    if (name.isEmpty) {
      throw CraftSvgProcessingException(
          CraftSvgExceptionMessageConstant.NAMED_OBJECT_NAME_NULL_OR_EMPTY);
    }
    if (!_namedObjects.containsKey(name)) {
      _namedObjects[name] = namedObject;
    }
  }

  CraftSvgNodeRenderer? getNamedObject(String name) => _namedObjects[name];
  CraftResourceResolver getResourceResolver() => _resourceResolver;
  CraftFontProvider getFontProvider() => _fontProvider;

  bool isIdUsedByUseTagBefore(String elementId) => _useIds.contains(elementId);
  void addUsedId(String elementId) => _useIds.addFirst(elementId);
  void removeUsedId(String elementId) => _useIds.removeFirst();

  CraftAffineTransform getRootTransform() {
    _rootTransform ??= CraftAffineTransform();
    return _rootTransform!;
  }

  void setRootTransform(CraftAffineTransform newTransform) =>
      _rootTransform = newTransform;

  List<double> getTextMove() => _textMove;
  void resetTextMove() => _textMove = [0.0, 0.0];
  void addTextMove(double additionalMoveX, double additionalMoveY) {
    _textMove[0] += additionalMoveX;
    _textMove[1] += additionalMoveY;
  }

  CraftAffineTransform getCurrentCanvasTransform() {
    return CraftAffineTransform.copy(
        getCurrentCanvas().getGraphicsState().getCtm());
  }

  CraftSvgCssContext getCssContext() => _cssContext;
  void setCssContext(CraftSvgCssContext cssContext) => _cssContext = cssContext;

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

  CraftAffineTransform getClippingElementTransform() =>
      _clippingElementTransform;
  void resetClippingElementTransform() =>
      _clippingElementTransform.setToIdentity();

  CraftAffineTransform getConcatenatedTransform() {
    List<CraftPdfCanvas> canvasList = [];
    int canvasesSize = size();
    for (int i = 0; i < canvasesSize; i++) {
      canvasList.add(popCanvas());
    }
    CraftAffineTransform transform = CraftAffineTransform();
    for (int i = canvasList.length - 1; i >= 0; i--) {
      CraftPdfCanvas pdfCanvas = canvasList[i];
      final matrix = pdfCanvas.getGraphicsState().getCtm();
      transform.concatenate(matrix);
      pushCanvas(pdfCanvas);
    }
    return transform;
  }
}
