import 'package:dpdf/src/styledxmlparser/css/common_css_constants.dart';
import 'package:dpdf/src/styledxmlparser/css/css_style_sheet.dart';
import 'package:dpdf/src/styledxmlparser/css/css_resolver.dart';
import 'package:dpdf/src/styledxmlparser/css/media/media_device_description.dart';
import 'package:dpdf/src/styledxmlparser/css/resolve/abstract_css_context.dart';
import 'package:dpdf/src/styledxmlparser/css/resolve/css_inheritance.dart';
import 'package:dpdf/src/styledxmlparser/css/resolve/style_inheritance.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_dimension_parsing_utils.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_types_validation_utils.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_variable_util.dart';
import 'package:dpdf/src/styledxmlparser/node/attribute.dart';
import 'package:dpdf/src/styledxmlparser/node/markup_node.dart';
import 'package:dpdf/src/styledxmlparser/node/styles_container.dart';
import 'package:dpdf/src/styledxmlparser/resolver/resource/resource_resolver.dart';
import 'package:dpdf/src/styledxmlparser/util/style_util.dart';
import 'package:dpdf/src/svg/css/impl/svg_attribute_inheritance.dart';
import 'package:dpdf/src/svg/css/svg_css_context.dart';
import 'package:dpdf/src/svg/exceptions/svg_processing_exception.dart';
import 'package:dpdf/src/svg/processors/impl/svg_processor_context.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Default implementation of SVG's styles and attribute resolver.
class CraftSvgStyleResolver implements CraftCssResolver {
  static final Set<CraftStyleInheritance> INHERITANCE_RULES = {
    CraftCssInheritance(),
    CraftSvgAttributeInheritance(),
  };

  static final double DEFAULT_FONT_SIZE =
      CraftCssDimensionParsingUtils.parseAbsoluteFontSize(
          "12pt"); // Default value for SVG font-size

  static const List<String> ELEMENTS_INHERITING_PARENT_STYLES = [
    SvgTags.MARKER,
    SvgTags.LINEAR_GRADIENT,
    SvgTags.PATTERN,
  ];

  late CraftCssStyleSheet css;
  bool isFirstSvgElement = true;
  late CraftMediaDeviceDescription deviceDescription;
  final List<CraftCssFontFaceRule> fonts = [];
  late CraftResourceResolver resourceResolver;

  CraftSvgStyleResolver(CraftSvgProcessorContext context) {
    this.css =
        CraftCssStyleSheet(); // In full version this would load default CSS
    this.resourceResolver = context.getResourceResolver();
    this.css.appendCssStyleSheet(context.getCssStyleSheet());
    this.deviceDescription = context.getDeviceDescription();
  }

  CraftSvgStyleResolver.fromRoot(
      CraftMarkupNode rootNode, CraftSvgProcessorContext context) {
    this.deviceDescription = context.getDeviceDescription();
    this.resourceResolver = context.getResourceResolver();
    this.css = CraftCssStyleSheet();
    this.css.appendCssStyleSheet(context.getCssStyleSheet());
    collectCssDeclarations(rootNode, this.resourceResolver);
    collectFonts();
  }

  static void resolveFontSizeStyle(Map<String, String> styles,
      CraftSvgCssContext? cssContext, String? parentFontSizeStr) {
    String? elementFontSize = styles[SvgAttributes.FONT_SIZE];
    String resolvedFontSize;
    if (CraftCssTypesValidationUtils.isNegativeValue(elementFontSize)) {
      elementFontSize = parentFontSizeStr;
    }
    if (CraftCssTypesValidationUtils.isRelativeValue(elementFontSize) ||
        CraftCommonCssConstants.LARGER == elementFontSize ||
        CraftCommonCssConstants.SMALLER == elementFontSize) {
      double baseFontSize;
      if (CraftCssTypesValidationUtils.isRemValue(elementFontSize)) {
        baseFontSize = cssContext == null
            ? DEFAULT_FONT_SIZE
            : cssContext.getRootFontSize();
      } else {
        if (parentFontSizeStr == null) {
          baseFontSize = DEFAULT_FONT_SIZE;
        } else {
          baseFontSize = CraftCssDimensionParsingUtils.parseAbsoluteLength(
              parentFontSizeStr);
        }
      }
      double absoluteFontSize =
          CraftCssDimensionParsingUtils.parseRelativeFontSize(
              elementFontSize!, baseFontSize);
      resolvedFontSize = absoluteFontSize.toStringAsFixed(4);
    } else {
      if (elementFontSize == null) {
        resolvedFontSize = DEFAULT_FONT_SIZE.toStringAsFixed(4);
      } else {
        resolvedFontSize =
            CraftCssDimensionParsingUtils.parseAbsoluteFontSize(elementFontSize)
                .toStringAsFixed(4);
      }
    }
    // Remove trailing zeros
    if (resolvedFontSize.contains('.')) {
      resolvedFontSize = resolvedFontSize
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.+$'), '');
    }
    styles[SvgAttributes.FONT_SIZE] =
        resolvedFontSize + CraftCommonCssConstants.PT;
  }

  static bool isElementNested(
      CraftElementNode element, String parentElementNameForSearch) {
    if (element.parentNode is! CraftElementNode) {
      return false;
    }
    CraftElementNode parentElement = element.parentNode as CraftElementNode;
    if (parentElement.name == parentElementNameForSearch) {
      return true;
    }
    return isElementNested(parentElement, parentElementNameForSearch);
  }

  @override
  Map<String, String> resolveStyles(
      CraftMarkupNode element, CraftAbstractCssContext context) {
    if (context is CraftSvgCssContext) {
      return _resolveStyles(element, context);
    }
    throw CraftSvgProcessingException(
        "Custom AbstractCssContext not supported");
  }

  Map<String, String> resolveNativeStyles(
      CraftMarkupNode node, CraftAbstractCssContext cssContext) {
    Map<String, String> styles = {};
    CraftAttribute? styleAttr;
    if (node is CraftElementNode) {
      for (CraftAttribute attr in node.getAttributes()) {
        if (SvgAttributes.STYLE == attr.getKey()) {
          styleAttr = attr;
        } else {
          _processAttribute(attr, styles);
        }
      }
    }
    // Load in from collected style sheets
    List<CraftCssDeclaration> styleSheetDeclarations = css.getCssDeclarations(
        node, CraftMediaDeviceDescription.createDefault());
    for (CraftCssDeclaration ssd in styleSheetDeclarations) {
      styles[ssd.getProperty()] = ssd.getExpression();
    }
    // Inline CSS from style attribute overrides
    if (styleAttr != null) {
      _processAttribute(styleAttr, styles);
    }
    return styles;
  }

  static bool _onlyNativeStylesShouldBeResolved(CraftElementNode element) {
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

  Map<String, String> _resolveStyles(
      CraftMarkupNode element, CraftSvgCssContext context) {
    Map<String, String> styles = resolveNativeStyles(element, context);
    Map<String, String>? parentStyles;
    if (element.parentNode is CraftStylesContainer) {
      CraftStylesContainer parentNode =
          element.parentNode as CraftStylesContainer;
      parentStyles = parentNode.getStyles();
    }

    if (element is CraftElementNode &&
        _onlyNativeStylesShouldBeResolved(element)) {
      _putMissingVariables(styles, parentStyles);
      CssVariableUtil.resolveCssVariables(styles);
      return styles;
    }

    String? parentFontSizeStr;
    if (parentStyles != null) {
      parentFontSizeStr = parentStyles[SvgAttributes.FONT_SIZE];
      parentStyles.forEach((key, value) {
        styles = CraftStyleUtil.mergeParentStyleDeclaration(
            styles, key, value, parentFontSizeStr ?? "", INHERITANCE_RULES);
      });
    }

    resolveFontSizeStyle(styles, context, parentFontSizeStr);

    // Process FONT_FAMILY (simplified)
    String? fontFamily = styles[CraftCommonCssConstants.FONT_FAMILY];
    if (fontFamily != null) {
      // Simplified: take first font family if split logic not yet implemented
      styles[CraftCommonCssConstants.FONT_FAMILY] =
          fontFamily.split(',')[0].trim();
    }

    CssVariableUtil.resolveCssVariables(styles);

    bool isSvgElement =
        element is CraftElementNode && SvgTags.SVG == element.name;
    if (isFirstSvgElement && isSvgElement) {
      isFirstSvgElement = false;
      String? rootFontSize = styles[SvgAttributes.FONT_SIZE];
      if (rootFontSize != null) {
        context.setRootFontSize(
            CraftCssDimensionParsingUtils.parseAbsoluteLength(rootFontSize));
      }
    }
    return styles;
  }

  void _processXLink(CraftAttribute attr, Map<String, String> attributesMap) {
    String xlinkValue = attr.getValue();
    if (!xlinkValue.startsWith('#') &&
        !CraftResourceResolver.isDataSrc(xlinkValue)) {
      xlinkValue = resourceResolver
          .resolveAgainstBaseUri(attr.getValue())
          .toExternalForm();
    }
    attributesMap[attr.getKey()] = xlinkValue;
  }

  void collectCssDeclarations(
      CraftMarkupNode rootNode, CraftResourceResolver resourceResolver) {
    List<CraftMarkupNode> q = [];
    q.add(rootNode);
    while (q.isNotEmpty) {
      CraftMarkupNode currentNode = q.removeAt(0);
      if (currentNode is CraftElementNode) {
        if (SvgTags.STYLE == currentNode.name) {
          for (CraftMarkupNode node in currentNode.childNodes) {
            if (node is CraftDataNode || node is CraftNode) {
              // Simplified: stylesheet parsing not yet fully implemented
            }
          }
        } else {
          // Check for stylesheet link (simplified)
        }
      } else if (currentNode is XmlDeclarationNode) {
        if (SvgTags.XML_STYLESHEET == currentNode.name) {
          // Parse stylesheet (simplified)
        }
      }
      q.addAll(currentNode.childNodes);
    }
  }

  void collectFonts() {
    for (CraftCssStatement cssStatement in css.getStatements()) {
      _collectFontsRecursive(cssStatement);
    }
  }

  void _collectFontsRecursive(CraftCssStatement cssStatement) {
    if (cssStatement is CraftCssFontFaceRule) {
      fonts.add(cssStatement);
    } else if (cssStatement is CraftCssMediaRule) {
      if (cssStatement.matchMediaDevice(deviceDescription)) {
        for (CraftCssStatement cssSubStatement
            in cssStatement.getStatements()) {
          _collectFontsRecursive(cssSubStatement);
        }
      }
    }
  }

  void _processAttribute(CraftAttribute attr, Map<String, String> styles) {
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
