import 'package:dpdf/src/styledxmlparser/css/common_css_constants.dart';
import 'package:dpdf/src/styledxmlparser/css/css_style_sheet.dart';
import 'package:dpdf/src/styledxmlparser/css/i_css_resolver.dart';
import 'package:dpdf/src/styledxmlparser/css/media/media_device_description.dart';
import 'package:dpdf/src/styledxmlparser/css/resolve/abstract_css_context.dart';
import 'package:dpdf/src/styledxmlparser/css/resolve/css_inheritance.dart';
import 'package:dpdf/src/styledxmlparser/css/resolve/i_style_inheritance.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_dimension_parsing_utils.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_types_validation_utils.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_variable_util.dart';
import 'package:dpdf/src/styledxmlparser/node/i_attribute.dart';
import 'package:dpdf/src/styledxmlparser/node/i_node.dart';
import 'package:dpdf/src/styledxmlparser/node/i_styles_container.dart';
import 'package:dpdf/src/styledxmlparser/resolver/resource/resource_resolver.dart';
import 'package:dpdf/src/styledxmlparser/util/style_util.dart';
import 'package:dpdf/src/svg/css/impl/svg_attribute_inheritance.dart';
import 'package:dpdf/src/svg/css/svg_css_context.dart';
import 'package:dpdf/src/svg/exceptions/svg_processing_exception.dart';
import 'package:dpdf/src/svg/processors/impl/svg_processor_context.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Default implementation of SVG's styles and attribute resolver.
class SvgStyleResolver implements ICssResolver {
  static final Set<IStyleInheritance> INHERITANCE_RULES = {
    CssInheritance(),
    SvgAttributeInheritance(),
  };

  static final double DEFAULT_FONT_SIZE =
      CssDimensionParsingUtils.parseAbsoluteFontSize(
          "12pt"); // Default value for SVG font-size

  static const List<String> ELEMENTS_INHERITING_PARENT_STYLES = [
    SvgTags.MARKER,
    SvgTags.LINEAR_GRADIENT,
    SvgTags.PATTERN,
  ];

  late CssStyleSheet css;
  bool isFirstSvgElement = true;
  late MediaDeviceDescription deviceDescription;
  final List<CssFontFaceRule> fonts = [];
  late ResourceResolver resourceResolver;

  SvgStyleResolver(SvgProcessorContext context) {
    this.css = CssStyleSheet(); // In full version this would load default CSS
    this.resourceResolver = context.getResourceResolver();
    this.css.appendCssStyleSheet(context.getCssStyleSheet());
    this.deviceDescription = context.getDeviceDescription();
  }

  SvgStyleResolver.fromRoot(INode rootNode, SvgProcessorContext context) {
    this.deviceDescription = context.getDeviceDescription();
    this.resourceResolver = context.getResourceResolver();
    this.css = CssStyleSheet();
    this.css.appendCssStyleSheet(context.getCssStyleSheet());
    collectCssDeclarations(rootNode, this.resourceResolver);
    collectFonts();
  }

  static void resolveFontSizeStyle(Map<String, String> styles,
      SvgCssContext? cssContext, String? parentFontSizeStr) {
    String? elementFontSize = styles[SvgAttributes.FONT_SIZE];
    String resolvedFontSize;
    if (CssTypesValidationUtils.isNegativeValue(elementFontSize)) {
      elementFontSize = parentFontSizeStr;
    }
    if (CssTypesValidationUtils.isRelativeValue(elementFontSize) ||
        CommonCssConstants.LARGER == elementFontSize ||
        CommonCssConstants.SMALLER == elementFontSize) {
      double baseFontSize;
      if (CssTypesValidationUtils.isRemValue(elementFontSize)) {
        baseFontSize = cssContext == null
            ? DEFAULT_FONT_SIZE
            : cssContext.getRootFontSize();
      } else {
        if (parentFontSizeStr == null) {
          baseFontSize = DEFAULT_FONT_SIZE;
        } else {
          baseFontSize =
              CssDimensionParsingUtils.parseAbsoluteLength(parentFontSizeStr);
        }
      }
      double absoluteFontSize = CssDimensionParsingUtils.parseRelativeFontSize(
          elementFontSize!, baseFontSize);
      resolvedFontSize = absoluteFontSize.toStringAsFixed(4);
    } else {
      if (elementFontSize == null) {
        resolvedFontSize = DEFAULT_FONT_SIZE.toStringAsFixed(4);
      } else {
        resolvedFontSize =
            CssDimensionParsingUtils.parseAbsoluteFontSize(elementFontSize)
                .toStringAsFixed(4);
      }
    }
    // Remove trailing zeros
    if (resolvedFontSize.contains('.')) {
      resolvedFontSize = resolvedFontSize
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.+$'), '');
    }
    styles[SvgAttributes.FONT_SIZE] = resolvedFontSize + CommonCssConstants.PT;
  }

  static bool isElementNested(
      IElementNode element, String parentElementNameForSearch) {
    if (element.parentNode is! IElementNode) {
      return false;
    }
    IElementNode parentElement = element.parentNode as IElementNode;
    if (parentElement.name == parentElementNameForSearch) {
      return true;
    }
    return isElementNested(parentElement, parentElementNameForSearch);
  }

  @override
  Map<String, String> resolveStyles(INode element, AbstractCssContext context) {
    if (context is SvgCssContext) {
      return _resolveStyles(element, context);
    }
    throw SvgProcessingException("Custom AbstractCssContext not supported");
  }

  Map<String, String> resolveNativeStyles(
      INode node, AbstractCssContext cssContext) {
    Map<String, String> styles = {};
    IAttribute? styleAttr;
    if (node is IElementNode) {
      for (IAttribute attr in node.getAttributes()) {
        if (SvgAttributes.STYLE == attr.getKey()) {
          styleAttr = attr;
        } else {
          _processAttribute(attr, styles);
        }
      }
    }
    // Load in from collected style sheets
    List<CssDeclaration> styleSheetDeclarations =
        css.getCssDeclarations(node, MediaDeviceDescription.createDefault());
    for (CssDeclaration ssd in styleSheetDeclarations) {
      styles[ssd.getProperty()] = ssd.getExpression();
    }
    // Inline CSS from style attribute overrides
    if (styleAttr != null) {
      _processAttribute(styleAttr, styles);
    }
    return styles;
  }

  static bool _onlyNativeStylesShouldBeResolved(IElementNode element) {
    for (String elementInheritingParentStyles
        in ELEMENTS_INHERITING_PARENT_STYLES) {
      if (elementInheritingParentStyles == element.name ||
          isElementNested(element, elementInheritingParentStyles)) {
        return false;
      }
    }
    return isElementNested(element, SvgTags.DEFS);
  }

  static void _putMissingVariables(
      Map<String, String> styles, Map<String, String>? parentStyles) {
    if (parentStyles == null) {
      return;
    }
    parentStyles.forEach((key, value) {
      if (CssVariableUtil.isCssVariable(key) && styles[key] == null) {
        styles[key] = value;
      }
    });
  }

  Map<String, String> _resolveStyles(INode element, SvgCssContext context) {
    Map<String, String> styles = resolveNativeStyles(element, context);
    Map<String, String>? parentStyles;
    if (element.parentNode is IStylesContainer) {
      IStylesContainer parentNode = element.parentNode as IStylesContainer;
      parentStyles = parentNode.getStyles();
    }

    if (element is IElementNode && _onlyNativeStylesShouldBeResolved(element)) {
      _putMissingVariables(styles, parentStyles);
      CssVariableUtil.resolveCssVariables(styles);
      return styles;
    }

    String? parentFontSizeStr;
    if (parentStyles != null) {
      parentFontSizeStr = parentStyles[SvgAttributes.FONT_SIZE];
      parentStyles.forEach((key, value) {
        styles = StyleUtil.mergeParentStyleDeclaration(
            styles, key, value, parentFontSizeStr ?? "", INHERITANCE_RULES);
      });
    }

    resolveFontSizeStyle(styles, context, parentFontSizeStr);

    // Process FONT_FAMILY (simplified)
    String? fontFamily = styles[CommonCssConstants.FONT_FAMILY];
    if (fontFamily != null) {
      // Simplified: take first font family if split logic not yet implemented
      styles[CommonCssConstants.FONT_FAMILY] = fontFamily.split(',')[0].trim();
    }

    CssVariableUtil.resolveCssVariables(styles);

    bool isSvgElement = element is IElementNode && SvgTags.SVG == element.name;
    if (isFirstSvgElement && isSvgElement) {
      isFirstSvgElement = false;
      String? rootFontSize = styles[SvgAttributes.FONT_SIZE];
      if (rootFontSize != null) {
        context.setRootFontSize(
            CssDimensionParsingUtils.parseAbsoluteLength(rootFontSize));
      }
    }
    return styles;
  }

  void _processXLink(IAttribute attr, Map<String, String> attributesMap) {
    String xlinkValue = attr.getValue();
    if (!xlinkValue.startsWith('#') &&
        !ResourceResolver.isDataSrc(xlinkValue)) {
      xlinkValue = resourceResolver
          .resolveAgainstBaseUri(attr.getValue())
          .toExternalForm();
    }
    attributesMap[attr.getKey()] = xlinkValue;
  }

  void collectCssDeclarations(
      INode rootNode, ResourceResolver resourceResolver) {
    List<INode> q = [];
    q.add(rootNode);
    while (q.isNotEmpty) {
      INode currentNode = q.removeAt(0);
      if (currentNode is IElementNode) {
        if (SvgTags.STYLE == currentNode.name) {
          for (INode node in currentNode.childNodes) {
            if (node is IDataNode || node is Node) {
              // Simplified: stylesheet parsing not yet fully implemented
            }
          }
        } else {
          // Check for stylesheet link (simplified)
        }
      } else if (currentNode is IXmlDeclarationNode) {
        if (SvgTags.XML_STYLESHEET == currentNode.name) {
          // Parse stylesheet (simplified)
        }
      }
      q.addAll(currentNode.childNodes);
    }
  }

  void collectFonts() {
    for (CssStatement cssStatement in css.getStatements()) {
      _collectFontsRecursive(cssStatement);
    }
  }

  void _collectFontsRecursive(CssStatement cssStatement) {
    if (cssStatement is CssFontFaceRule) {
      fonts.add(cssStatement);
    } else if (cssStatement is CssMediaRule) {
      if (cssStatement.matchMediaDevice(deviceDescription)) {
        for (CssStatement cssSubStatement in cssStatement.getStatements()) {
          _collectFontsRecursive(cssSubStatement);
        }
      }
    }
  }

  void _processAttribute(IAttribute attr, Map<String, String> styles) {
    switch (attr.getKey()) {
      case SvgAttributes.STYLE:
        // Simplified: parse styles from style attribute
        break;
      case SvgAttributes.XLINK_HREF:
        _processXLink(attr, styles);
        break;
      default:
        styles[attr.getKey()] = attr.getValue();
        break;
    }
  }
}
