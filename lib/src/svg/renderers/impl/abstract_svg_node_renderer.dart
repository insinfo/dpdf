import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/colors/color_constants.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/extgstate/pdf_ext_g_state.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/layout/properties/transparent_color.dart';
import 'package:dpdf/src/styledxmlparser/css/common_css_constants.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_dimension_parsing_utils.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_types_validation_utils.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_utils.dart';
import 'package:dpdf/src/svg/css/svg_stroke_parameter_converter.dart';
import 'package:dpdf/src/svg/marker_vertex_type.dart';
import 'package:dpdf/src/svg/renderers/marker_capable.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_paint_server.dart';
import 'package:dpdf/src/svg/renderers/svg_shading_paint_server.dart';
import 'package:dpdf/src/svg/renderers/svg_text_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_color_utils.dart';
import 'package:dpdf/src/svg/utils/svg_css_utils.dart';
import 'package:dpdf/src/svg/utils/transform_utils.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_container_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/clip_path_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/marker_svg_node_renderer.dart';
import 'package:dpdf/src/svg/css/impl/svg_node_renderer_inheritance_resolver.dart';

abstract class AbstractSvgNodeRenderer implements SvgNodeRenderer {
  static final List<MarkerVertexType> _MARKER_VERTEX_TYPES = [
    MarkerVertexType.MARKER_START,
    MarkerVertexType.MARKER_MID,
    MarkerVertexType.MARKER_END
  ];

  Map<String, String>? _attributesAndStyles;
  bool doFill = false;
  bool doStroke = false;
  SvgNodeRenderer? _parent;

  @override
  void setParent(SvgNodeRenderer? parent) {
    _parent = parent;
  }

  @override
  SvgNodeRenderer? getParent() => _parent;

  @override
  void setAttributesAndStyles(Map<String, String> attributesAndStyles) {
    _attributesAndStyles = attributesAndStyles;
  }

  @override
  String? getAttribute(String key) {
    return _attributesAndStyles?[key];
  }

  String getAttributeOrDefault(String key, String defaultValue) {
    return getAttribute(key) ?? defaultValue;
  }

  @override
  void setAttribute(String key, String value) {
    _attributesAndStyles ??= {};
    _attributesAndStyles![key] = value;
  }

  @override
  Map<String, String> getAttributeMapCopy() {
    return Map<String, String>.from(_attributesAndStyles ?? {});
  }

  @override
  Future<void> draw(SvgDrawContext context) async {
    if (_attributesAndStyles != null) {
      if (isHidden()) {
        return;
      }
      String? transformString = getAttribute(SvgAttributes.TRANSFORM);
      if (transformString != null && transformString.trim().isNotEmpty) {
        // O `cm` fica sem q/Q próprio: quem empilha o estado é o renderizador
        // do galho, que envolve cada filho, para uma transformação declarada
        // num `<g>` alcançar toda a sua subárvore.
        final transformation = TransformUtils.parseTransform(transformString);
        if (!transformation.isIdentity) {
          context.getCurrentCanvas().concatMatrix(
              transformation.m00,
              transformation.m10,
              transformation.m01,
              transformation.m11,
              transformation.m02,
              transformation.m12);
        }
      }
      if (_attributesAndStyles!.containsKey(SvgAttributes.ID)) {
        context.addUsedId(_attributesAndStyles![SvgAttributes.ID]!);
      }
    }

    if (!await _drawInClipPath(context)) {
      await preDraw(context);
      await doDraw(context);
      await postDraw(context);
    }

    if (_attributesAndStyles != null &&
        _attributesAndStyles!.containsKey(SvgAttributes.ID)) {
      context.removeUsedId(_attributesAndStyles![SvgAttributes.ID]!);
    }
  }

  bool isHidden() {
    return CommonCssConstants.NONE ==
            getAttribute(CommonCssConstants.DISPLAY) ||
        CommonCssConstants.HIDDEN ==
            getAttribute(CommonCssConstants.VISIBILITY);
  }

  bool canElementFill() => true;

  bool canConstructViewPort() => false;

  double getCurrentFontSize(SvgDrawContext context) {
    String? fontSizeAttribute = getAttribute(SvgAttributes.FONT_SIZE);
    if (CssTypesValidationUtils.isRemValue(fontSizeAttribute)) {
      return CssDimensionParsingUtils.parseRelativeValue(
          fontSizeAttribute!, context.getCssContext().getRootFontSize());
    }
    final parent = getParent();
    if (CssTypesValidationUtils.isEmValue(fontSizeAttribute) &&
        parent is AbstractSvgNodeRenderer) {
      return CssDimensionParsingUtils.parseRelativeValue(
          fontSizeAttribute!, parent.getCurrentFontSize(context));
    }
    return CssDimensionParsingUtils.parseAbsoluteFontSize(fontSizeAttribute);
  }

  void deepCopyAttributesAndStyles(SvgNodeRenderer deepCopy) {
    if (_attributesAndStyles != null) {
      deepCopy.setAttributesAndStyles(
          Map<String, String>.from(_attributesAndStyles!));
    }
  }

  Rectangle getCurrentViewBox(SvgDrawContext context) {
    if (this is AbstractContainerSvgNodeRenderer) {
      List<double>? viewBoxValues = SvgCssUtils.parseViewBox(this);
      if (viewBoxValues == null ||
          viewBoxValues.length < SvgValues.VIEWBOX_VALUES_NUMBER) {
        Rectangle? currentViewPort = context.getCurrentViewPort();
        if (currentViewPort == null) return Rectangle(0, 0, 0, 0);
        return Rectangle(
            0, 0, currentViewPort.getWidth(), currentViewPort.getHeight());
      }
      return Rectangle(viewBoxValues[0], viewBoxValues[1], viewBoxValues[2],
          viewBoxValues[3]);
    } else {
      final parent = getParent();
      if (parent is AbstractSvgNodeRenderer) {
        return parent.getCurrentViewBox(context);
      } else {
        return context.getCurrentViewPort() ?? Rectangle(0, 0, 0, 0);
      }
    }
  }

  Future<void> preDraw(SvgDrawContext context) async {
    if (_attributesAndStyles != null && getParentClipPath() == null) {
      FillProperties? fillProps = _calculateFillProperties(context);
      StrokeProperties? strokeProps = _calculateStrokeProperties(context);
      await _applyFillAndStrokeProperties(fillProps, strokeProps, context);
    }
  }

  Future<void> postDraw(SvgDrawContext context) async {
    if (_attributesAndStyles != null) {
      PdfCanvas currentCanvas = context.getCurrentCanvas();
      if (this is SvgTextNodeRenderer) {
        return;
      }

      // Filhos de um clipPath apenas acrescentam sua geometria ao caminho
      // corrente. Aplicar W após cada filho faria interseção entre as formas;
      // SVG define a união delas como uma única máscara de recorte.
      if (getParentClipPath() != null && this is! ClipPathSvgNodeRenderer) {
        return;
      }

      final shading = _shadingPaintServer(context);
      if (doFill && shading != null) {
        final fillRule = getAttributeOrDefault(SvgAttributes.FILL_RULE, '');
        currentCanvas.saveState();
        if (fillRule.toLowerCase() == SvgValues.FILL_RULE_EVEN_ODD) {
          currentCanvas.eoClip();
        } else {
          currentCanvas.clip();
        }
        currentCanvas.newPath();
        await shading.paintShading(
            context, getObjectBoundingBox(context) ?? Rectangle(0, 0, 0, 0));
        currentCanvas.restoreState();
        if (doStroke) {
          // O operador de clip consome o caminho; reconstrua apenas para o
          // traço, mantendo shading e stroke semanticamente independentes.
          await doDraw(context);
          currentCanvas.stroke();
        } else {
          currentCanvas.newPath();
        }
        await _drawMarkers(context);
        return;
      }

      if (getParentClipPath() == null) {
        if (doFill && canElementFill()) {
          String fillRule = getAttributeOrDefault(SvgAttributes.FILL_RULE, "");
          _doStrokeOrFill(fillRule, currentCanvas);
        } else {
          if (doStroke) {
            currentCanvas.stroke();
          } else {
            currentCanvas.newPath();
          }
        }
      } else {
        String clipRule = getAttributeOrDefault(SvgAttributes.CLIP_RULE, "");
        if (clipRule.toLowerCase() == SvgValues.FILL_RULE_EVEN_ODD) {
          currentCanvas.eoClip();
        } else {
          currentCanvas.clip();
        }
        currentCanvas.newPath();
      }

      await _drawMarkers(context);
    }
  }

  Future<void> _drawMarkers(SvgDrawContext context) async {
    if (this is! MarkerCapable || _attributesAndStyles == null) return;
    final vertices = (this as MarkerCapable).markerVertices(context);
    if (vertices.isEmpty) return;
    final strokeWidth = parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.STROKE_WIDTH, '1'), context);
    for (final type in _MARKER_VERTEX_TYPES) {
      final raw =
          getAttribute(type.toString()) ?? getAttribute(SvgAttributes.MARKER);
      if (raw == null || !raw.startsWith('url(')) continue;
      final id = raw.replaceAll('url(#', '').replaceAll(')', '').trim();
      final marker = context.getNamedObject(CssUtils.extractUnquotedString(id));
      if (marker is! MarkerSvgNodeRenderer) continue;
      final selected = type == MarkerVertexType.MARKER_START
          ? vertices.where((vertex) => vertex.isStart)
          : type == MarkerVertexType.MARKER_END
              ? vertices.where((vertex) => vertex.isEnd)
              : vertices.where((vertex) => !vertex.isStart && !vertex.isEnd);
      for (final vertex in selected) {
        await marker.drawAt(context, vertex, type, strokeWidth);
      }
    }
  }

  SvgShadingPaintServer? _shadingPaintServer(SvgDrawContext context) {
    final raw = getAttribute(SvgAttributes.FILL);
    if (raw == null || !raw.startsWith('url(')) return null;
    final id = raw.replaceAll('url(#', '').replaceAll(')', '').trim();
    final renderer = context.getNamedObject(CssUtils.extractUnquotedString(id));
    return renderer is SvgShadingPaintServer ? renderer : null;
  }

  void _doStrokeOrFill(String fillRule, PdfCanvas currentCanvas) {
    if (fillRule.toLowerCase() == SvgValues.FILL_RULE_EVEN_ODD) {
      if (doStroke) {
        currentCanvas.eoFillStroke();
      } else {
        currentCanvas.eoFill();
      }
    } else {
      if (doStroke) {
        currentCanvas.fillStroke();
      } else {
        currentCanvas.fill();
      }
    }
  }

  Future<void> _applyFillAndStrokeProperties(FillProperties? fillProps,
      StrokeProperties? strokeProps, SvgDrawContext context) async {
    PdfExtGState opacityGState = PdfExtGState();
    PdfCanvas currentCanvas = context.getCurrentCanvas();

    if (fillProps != null) {
      currentCanvas.setFillColor(fillProps.color);
      if (!CssUtils.compareFloats(fillProps.opacity, 1.0)) {
        opacityGState.setFillOpacity(fillProps.opacity);
      }
    }

    if (strokeProps != null) {
      if (strokeProps.color != null) {
        currentCanvas.setStrokeColor(strokeProps.color!);
      }
      currentCanvas.setLineWidth(strokeProps.width);
      final dash = strokeProps.lineDashParameters;
      if (dash != null && dash.getDashArray().isNotEmpty) {
        currentCanvas.setDashPattern(
            PdfArray.fromDoubles(dash.getDashArray()), dash.getDashPhase());
      }
      if (!CssUtils.compareFloats(strokeProps.opacity, 1.0)) {
        opacityGState.setStrokeOpacity(strokeProps.opacity);
      }
    }

    // O ExtGState precisa de dicionário de recursos e de documento para virar
    // um nome. Desenhar num canvas solto (sem documento) é legítimo — e é o
    // que os testes fazem — então a transparência é simplesmente omitida em
    // vez de derrubar a conversão inteira.
    final canUseExtGState =
        currentCanvas.resources != null && currentCanvas.getDocument() != null;
    if (canUseExtGState && !opacityGState.pdfRepresentation().isEmpty()) {
      await currentCanvas.setExtGState(opacityGState);
    }
  }

  FillProperties? _calculateFillProperties(SvgDrawContext context) {
    double generalOpacity = _getOpacity();
    String fillRaw = getAttributeOrDefault(SvgAttributes.FILL, "black");
    doFill = fillRaw.toLowerCase() != SvgValues.NONE;

    // Shadings pintam o preenchimento depois de o caminho virar clipping.
    // Não os converta no fallback transparente de um paint server comum:
    // esse alfa também tornaria invisível o operador `sh` subsequente.
    if (doFill && _shadingPaintServer(context) != null) return null;

    if (doFill && canElementFill()) {
      double fillOpacity =
          _getOpacityByAttribute(SvgAttributes.FILL_OPACITY, generalOpacity);
      Color fillColor = ColorConstants.BLACK;
      TransparentColor? tc =
          _getColorFromAttribute(context, fillRaw, 0, fillOpacity);
      if (tc != null) {
        fillColor = tc.getColor();
        fillOpacity = tc.getOpacity();
      }
      return FillProperties(fillOpacity, fillColor);
    }
    return null;
  }

  StrokeProperties? _calculateStrokeProperties(SvgDrawContext context) {
    String strokeRaw =
        getAttributeOrDefault(SvgAttributes.STROKE, SvgValues.NONE);
    if (strokeRaw.toLowerCase() != SvgValues.NONE) {
      String? widthRaw = getAttribute(SvgAttributes.STROKE_WIDTH);
      double width =
          widthRaw != null ? parseHorizontalLength(widthRaw, context) : 0.75;
      if (width < 0) width = 0.75;

      double generalOpacity = _getOpacity();
      double opacity =
          _getOpacityByAttribute(SvgAttributes.STROKE_OPACITY, generalOpacity);
      Color? strokeColor;
      TransparentColor? tc =
          _getColorFromAttribute(context, strokeRaw, width / 2.0, opacity);
      if (tc != null) {
        strokeColor = tc.getColor();
        opacity = tc.getOpacity();
      }

      String? dashArrayRaw = getAttribute(SvgAttributes.STROKE_DASHARRAY);
      String? dashOffsetRaw = getAttribute(SvgAttributes.STROKE_DASHOFFSET);
      PdfLineDashParameters? dashParams =
          SvgStrokeParameterConverter.convertStrokeDashParameters(dashArrayRaw,
              dashOffsetRaw, getCurrentFontSize(context), context);

      if (width > 0) {
        doStroke = true;
        return StrokeProperties(strokeColor, width, opacity, dashParams);
      }
    }
    return null;
  }

  double _getOpacity() {
    double result = 1.0;
    String? val = getAttribute(SvgAttributes.OPACITY);
    if (val != null && val.toLowerCase() != SvgValues.NONE) {
      result = double.tryParse(val) ?? 1.0;
    }
    final parent = getParent();
    if (parent is AbstractSvgNodeRenderer) {
      result *= parent._getOpacity();
    }
    return result;
  }

  double _getOpacityByAttribute(String attrName, double generalOpacity) {
    double opacity = generalOpacity;
    String? val = getAttribute(attrName);
    if (val != null && val.toLowerCase() != SvgValues.NONE) {
      double valNum;
      if (CssTypesValidationUtils.isPercentageValue(val)) {
        valNum = CssDimensionParsingUtils.parseRelativeValue(val, 1.0);
      } else {
        valNum = double.tryParse(val) ?? 1.0;
      }
      opacity *= valNum;
    }
    return opacity;
  }

  TransparentColor? _getColorFromAttribute(
      SvgDrawContext context, String raw, double margin, double parentOpacity) {
    if (raw.toLowerCase() == CommonCssConstants.CURRENTCOLOR) {
      raw = getAttributeOrDefault(CommonCssConstants.COLOR, "black");
    }

    if (raw.startsWith("url(")) {
      String id = raw.replaceAll("url(#", "").replaceAll(")", "").trim();
      id = CssUtils.extractUnquotedString(id);
      SvgNodeRenderer? colorRenderer = context.getNamedObject(id);
      if (colorRenderer is SvgPaintServer) {
        if (colorRenderer.getParent() == null) {
          colorRenderer.setParent(this);
        }
        Color? resolvedColor = colorRenderer.createColor(
            context,
            getObjectBoundingBox(context) ?? Rectangle(0, 0, 0, 0),
            margin,
            parentOpacity);
        if (resolvedColor != null) {
          return TransparentColor(resolvedColor, 1.0);
        }
      }
      return TransparentColor(ColorConstants.BLACK, 0.0);
    }

    if (raw.toLowerCase() == SvgValues.NONE) return null;

    // Um valor incompreensível equivale a preto: a especificação manda tratar
    // a cor inválida como o padrão herdado, nunca abortar o desenho.
    final parsed = SvgColorUtils.parse(raw);
    return TransparentColor(parsed ?? ColorConstants.BLACK, parentOpacity);
  }

  double parseHorizontalLength(String length, SvgDrawContext context) {
    return SvgCssUtils.parseAbsoluteHorizontalLength(
        this, length, 0.0, context);
  }

  double parseVerticalLength(String length, SvgDrawContext context) {
    return SvgCssUtils.parseAbsoluteVerticalLength(this, length, 0.0, context);
  }

  Future<bool> _drawInClipPath(SvgDrawContext context) async {
    String? clipPathName = getAttribute(SvgAttributes.CLIP_PATH);
    if (clipPathName != null) {
      String id =
          clipPathName.replaceAll("url(#", "").replaceAll(")", "").trim();
      SvgNodeRenderer? template = context.getNamedObject(id);
      if (template is ClipPathSvgNodeRenderer) {
        ClipPathSvgNodeRenderer clipPath =
            template.createDeepCopy() as ClipPathSvgNodeRenderer;
        if (clipPath.isHidden()) return false;

        SvgNodeRendererInheritanceResolver.applyInheritanceToSubTree(
            this, clipPath, context.getCssContext());
        clipPath.setClippedRenderer(this);
        await clipPath.draw(context);
        return true;
      }
    }
    return false;
  }

  ClipPathSvgNodeRenderer? getParentClipPath() {
    if (this is ClipPathSvgNodeRenderer) {
      return this as ClipPathSvgNodeRenderer;
    }
    final parent = getParent();
    if (parent is AbstractSvgNodeRenderer) {
      return parent.getParentClipPath();
    }
    return null;
  }

  Future<void> doDraw(SvgDrawContext context);

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context);

  @override
  SvgNodeRenderer createDeepCopy();
}

class FillProperties {
  final double opacity;
  final Color color;
  FillProperties(this.opacity, this.color);
}

class StrokeProperties {
  final Color? color;
  final double width;
  final double opacity;
  final PdfLineDashParameters? lineDashParameters;
  StrokeProperties(
      this.color, this.width, this.opacity, this.lineDashParameters);
}
