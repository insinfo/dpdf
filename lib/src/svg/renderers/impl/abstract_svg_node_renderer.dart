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
import 'package:dpdf/src/svg/renderers/svg_text_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_color_utils.dart';
import 'package:dpdf/src/svg/utils/svg_css_utils.dart';
import 'package:dpdf/src/svg/utils/transform_utils.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_container_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/clip_path_svg_node_renderer.dart';
import 'package:dpdf/src/svg/css/impl/svg_node_renderer_inheritance_resolver.dart';

abstract class CraftAbstractSvgNodeRenderer implements CraftSvgNodeRenderer {
  static final List<CraftMarkerVertexType> _MARKER_VERTEX_TYPES = [
    CraftMarkerVertexType.MARKER_START,
    CraftMarkerVertexType.MARKER_MID,
    CraftMarkerVertexType.MARKER_END
  ];

  Map<String, String>? _attributesAndStyles;
  bool doFill = false;
  bool doStroke = false;
  CraftSvgNodeRenderer? _parent;

  @override
  void setParent(CraftSvgNodeRenderer? parent) {
    _parent = parent;
  }

  @override
  CraftSvgNodeRenderer? getParent() => _parent;

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
  Future<void> draw(CraftSvgDrawContext context) async {
    if (_attributesAndStyles != null) {
      if (isHidden()) {
        return;
      }
      String? transformString = getAttribute(SvgAttributes.TRANSFORM);
      if (transformString != null && transformString.trim().isNotEmpty) {
        // O `cm` fica sem q/Q próprio: quem empilha o estado é o renderizador
        // do galho, que envolve cada filho, para uma transformação declarada
        // num `<g>` alcançar toda a sua subárvore.
        final transformation =
            CraftTransformUtils.parseTransform(transformString);
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
    return CraftCommonCssConstants.NONE ==
            getAttribute(CraftCommonCssConstants.DISPLAY) ||
        CraftCommonCssConstants.HIDDEN ==
            getAttribute(CraftCommonCssConstants.VISIBILITY);
  }

  bool canElementFill() => true;

  bool canConstructViewPort() => false;

  double getCurrentFontSize(CraftSvgDrawContext context) {
    String? fontSizeAttribute = getAttribute(SvgAttributes.FONT_SIZE);
    if (CraftCssTypesValidationUtils.isRemValue(fontSizeAttribute)) {
      return CraftCssDimensionParsingUtils.parseRelativeValue(
          fontSizeAttribute!, context.getCssContext().getRootFontSize());
    }
    final parent = getParent();
    if (CraftCssTypesValidationUtils.isEmValue(fontSizeAttribute) &&
        parent is CraftAbstractSvgNodeRenderer) {
      return CraftCssDimensionParsingUtils.parseRelativeValue(
          fontSizeAttribute!, parent.getCurrentFontSize(context));
    }
    return CraftCssDimensionParsingUtils.parseAbsoluteFontSize(
        fontSizeAttribute);
  }

  void deepCopyAttributesAndStyles(CraftSvgNodeRenderer deepCopy) {
    if (_attributesAndStyles != null) {
      deepCopy.setAttributesAndStyles(
          Map<String, String>.from(_attributesAndStyles!));
    }
  }

  CraftRectangle getCurrentViewBox(CraftSvgDrawContext context) {
    if (this is CraftAbstractContainerSvgNodeRenderer) {
      List<double>? viewBoxValues = CraftSvgCssUtils.parseViewBox(this);
      if (viewBoxValues == null ||
          viewBoxValues.length < SvgValues.VIEWBOX_VALUES_NUMBER) {
        CraftRectangle? currentViewPort = context.getCurrentViewPort();
        if (currentViewPort == null) return CraftRectangle(0, 0, 0, 0);
        return CraftRectangle(
            0, 0, currentViewPort.getWidth(), currentViewPort.getHeight());
      }
      return CraftRectangle(viewBoxValues[0], viewBoxValues[1],
          viewBoxValues[2], viewBoxValues[3]);
    } else {
      final parent = getParent();
      if (parent is CraftAbstractSvgNodeRenderer) {
        return parent.getCurrentViewBox(context);
      } else {
        return context.getCurrentViewPort() ?? CraftRectangle(0, 0, 0, 0);
      }
    }
  }

  Future<void> preDraw(CraftSvgDrawContext context) async {
    if (_attributesAndStyles != null && getParentClipPath() == null) {
      FillProperties? fillProps = _calculateFillProperties(context);
      StrokeProperties? strokeProps = _calculateStrokeProperties(context);
      await _applyFillAndStrokeProperties(fillProps, strokeProps, context);
    }
  }

  Future<void> postDraw(CraftSvgDrawContext context) async {
    if (_attributesAndStyles != null) {
      CraftPdfCanvas currentCanvas = context.getCurrentCanvas();
      if (this is CraftSvgTextNodeRenderer) {
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

      if (this is CraftMarkerCapable) {
        for (var markerType in _MARKER_VERTEX_TYPES) {
          if (_attributesAndStyles!.containsKey(markerType.toString())) {
            (this as CraftMarkerCapable).drawMarker(context, markerType);
          }
        }
      }
    }
  }

  void _doStrokeOrFill(String fillRule, CraftPdfCanvas currentCanvas) {
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
      StrokeProperties? strokeProps, CraftSvgDrawContext context) async {
    CraftPdfExtGState opacityGState = CraftPdfExtGState();
    CraftPdfCanvas currentCanvas = context.getCurrentCanvas();

    if (fillProps != null) {
      currentCanvas.setFillColor(fillProps.color);
      if (!CraftCssUtils.compareFloats(fillProps.opacity, 1.0)) {
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
            CraftPdfArray.fromDoubles(dash.getDashArray()),
            dash.getDashPhase());
      }
      if (!CraftCssUtils.compareFloats(strokeProps.opacity, 1.0)) {
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

  FillProperties? _calculateFillProperties(CraftSvgDrawContext context) {
    double generalOpacity = _getOpacity();
    String fillRaw = getAttributeOrDefault(SvgAttributes.FILL, "black");
    doFill = fillRaw.toLowerCase() != SvgValues.NONE;

    if (doFill && canElementFill()) {
      double fillOpacity =
          _getOpacityByAttribute(SvgAttributes.FILL_OPACITY, generalOpacity);
      CraftColor fillColor = CraftColorConstants.BLACK;
      CraftTransparentColor? tc =
          _getColorFromAttribute(context, fillRaw, 0, fillOpacity);
      if (tc != null) {
        fillColor = tc.getColor();
        fillOpacity = tc.getOpacity();
      }
      return FillProperties(fillOpacity, fillColor);
    }
    return null;
  }

  StrokeProperties? _calculateStrokeProperties(CraftSvgDrawContext context) {
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
      CraftColor? strokeColor;
      CraftTransparentColor? tc =
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
    if (parent is CraftAbstractSvgNodeRenderer) {
      result *= parent._getOpacity();
    }
    return result;
  }

  double _getOpacityByAttribute(String attrName, double generalOpacity) {
    double opacity = generalOpacity;
    String? val = getAttribute(attrName);
    if (val != null && val.toLowerCase() != SvgValues.NONE) {
      double valNum;
      if (CraftCssTypesValidationUtils.isPercentageValue(val)) {
        valNum = CraftCssDimensionParsingUtils.parseRelativeValue(val, 1.0);
      } else {
        valNum = double.tryParse(val) ?? 1.0;
      }
      opacity *= valNum;
    }
    return opacity;
  }

  CraftTransparentColor? _getColorFromAttribute(CraftSvgDrawContext context,
      String raw, double margin, double parentOpacity) {
    if (raw.toLowerCase() == CraftCommonCssConstants.CURRENTCOLOR) {
      raw = getAttributeOrDefault(CraftCommonCssConstants.COLOR, "black");
    }

    if (raw.startsWith("url(")) {
      String id = raw.replaceAll("url(#", "").replaceAll(")", "").trim();
      id = CraftCssUtils.extractUnquotedString(id);
      CraftSvgNodeRenderer? colorRenderer = context.getNamedObject(id);
      if (colorRenderer is CraftSvgPaintServer) {
        if (colorRenderer.getParent() == null) {
          colorRenderer.setParent(this);
        }
        CraftColor? resolvedColor = colorRenderer.createColor(
            context,
            getObjectBoundingBox(context) ?? CraftRectangle(0, 0, 0, 0),
            margin,
            parentOpacity);
        if (resolvedColor != null) {
          return CraftTransparentColor(resolvedColor, 1.0);
        }
      }
      return CraftTransparentColor(CraftColorConstants.BLACK, 0.0);
    }

    if (raw.toLowerCase() == SvgValues.NONE) return null;

    // Um valor incompreensível equivale a preto: a especificação manda tratar
    // a cor inválida como o padrão herdado, nunca abortar o desenho.
    final parsed = CraftSvgColorUtils.parse(raw);
    return CraftTransparentColor(
        parsed ?? CraftColorConstants.BLACK, parentOpacity);
  }

  double parseHorizontalLength(String length, CraftSvgDrawContext context) {
    return CraftSvgCssUtils.parseAbsoluteHorizontalLength(
        this, length, 0.0, context);
  }

  double parseVerticalLength(String length, CraftSvgDrawContext context) {
    return CraftSvgCssUtils.parseAbsoluteVerticalLength(
        this, length, 0.0, context);
  }

  Future<bool> _drawInClipPath(CraftSvgDrawContext context) async {
    String? clipPathName = getAttribute(SvgAttributes.CLIP_PATH);
    if (clipPathName != null) {
      String id =
          clipPathName.replaceAll("url(#", "").replaceAll(")", "").trim();
      CraftSvgNodeRenderer? template = context.getNamedObject(id);
      if (template is CraftClipPathSvgNodeRenderer) {
        CraftClipPathSvgNodeRenderer clipPath =
            template.createDeepCopy() as CraftClipPathSvgNodeRenderer;
        if (clipPath.isHidden()) return false;

        CraftSvgNodeRendererInheritanceResolver.applyInheritanceToSubTree(
            this, clipPath, context.getCssContext());
        clipPath.setClippedRenderer(this);
        await clipPath.draw(context);
        return true;
      }
    }
    return false;
  }

  CraftClipPathSvgNodeRenderer? getParentClipPath() {
    if (this is CraftClipPathSvgNodeRenderer) {
      return this as CraftClipPathSvgNodeRenderer;
    }
    final parent = getParent();
    if (parent is CraftAbstractSvgNodeRenderer) {
      return parent.getParentClipPath();
    }
    return null;
  }

  Future<void> doDraw(CraftSvgDrawContext context);

  @override
  CraftRectangle? getObjectBoundingBox(CraftSvgDrawContext context);

  @override
  CraftSvgNodeRenderer createDeepCopy();
}

class FillProperties {
  final double opacity;
  final CraftColor color;
  FillProperties(this.opacity, this.color);
}

class StrokeProperties {
  final CraftColor? color;
  final double width;
  final double opacity;
  final PdfLineDashParameters? lineDashParameters;
  StrokeProperties(
      this.color, this.width, this.opacity, this.lineDashParameters);
}
