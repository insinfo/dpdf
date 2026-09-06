import 'dart:math' as math;

import 'package:pdfcraft/src/io/font/constants/standard_fonts.dart';
import 'package:pdfcraft/src/kernel/font/pdf_font_factory.dart';
import 'package:pdfcraft/src/kernel/numbering/english_alphabet_numbering.dart';
import 'package:pdfcraft/src/kernel/numbering/greek_alphabet_numbering.dart';
import 'package:pdfcraft/src/kernel/numbering/roman_numbering.dart';
import 'package:pdfcraft/src/layout/element/list.dart' as elements;
import 'package:pdfcraft/src/layout/element/text.dart';
import 'package:pdfcraft/src/layout/element/image.dart';
import 'package:pdfcraft/src/layout/layout/layout_context.dart';
import 'package:pdfcraft/src/layout/layout/layout_result.dart';
import 'package:pdfcraft/src/layout/layout/layout_area.dart';
import 'package:pdfcraft/src/layout/properties/list_numbering_type.dart';
import 'package:pdfcraft/src/layout/properties/list_symbol_position.dart';
import 'package:pdfcraft/src/layout/properties/property.dart';
import 'package:pdfcraft/src/layout/properties/unit_value.dart';
import 'package:pdfcraft/src/layout/renderer/abstract_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/block_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/draw_context.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';
import 'package:pdfcraft/src/layout/renderer/line_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/list_item_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/text_renderer.dart';

class CraftListRenderer extends CraftBlockRenderer {
  CraftListRenderer(elements.CraftList modelElement) : super(modelElement);

  @override
  CraftLayoutResult? layout(CraftLayoutContext layoutContext) {
    CraftLayoutResult? errorResult = _initializeListSymbols(layoutContext);
    if (errorResult != null) {
      return errorResult;
    }
    CraftLayoutResult? result = super.layout(layoutContext);
    if (result == null) return null;

    // cannot place even the first ListItemRenderer
    if (true == getPropertyAsBoolean(CraftProperty.FORCED_PLACEMENT) &&
        result.getCauseOfNothing() != null) {
      if (CraftLayoutResult.FULL == result.getStatus()) {
        result = _correctListSplitting(
            this, null, result.getCauseOfNothing()!, result.getOccupiedArea()!);
      } else if (CraftLayoutResult.PARTIAL == result.getStatus()) {
        result = _correctListSplitting(
            result.getSplitRenderer()!,
            result.getOverflowRenderer(),
            result.getCauseOfNothing()!,
            result.getOccupiedArea()!);
      }
    }
    return result;
  }

  @override
  CraftRenderer getNextRenderer() {
    return CraftListRenderer(modelElement as elements.CraftList);
  }

  @override
  CraftAbstractRenderer createSplitRenderer(int layoutResult) {
    CraftAbstractRenderer splitRenderer =
        super.createSplitRenderer(layoutResult);
    splitRenderer.addAllProperties(getOwnProperties());
    splitRenderer.setProperty(CraftProperty.LIST_SYMBOLS_INITIALIZED, true);
    return splitRenderer;
  }

  @override
  CraftAbstractRenderer createOverflowRenderer(int layoutResult) {
    CraftAbstractRenderer overflowRenderer =
        super.createOverflowRenderer(layoutResult);
    overflowRenderer.addAllProperties(getOwnProperties());
    overflowRenderer.setProperty(CraftProperty.LIST_SYMBOLS_INITIALIZED, true);
    return overflowRenderer;
  }

  CraftRenderer? makeListSymbolRenderer(int index, CraftRenderer renderer) {
    CraftRenderer? symbolRenderer = _createListSymbolRenderer(index, renderer);
    if (symbolRenderer != null) {
      symbolRenderer.setProperty(CraftProperty.UNDERLINE, false);
    }
    return symbolRenderer;
  }

  static Object? getListItemOrListProperty(
      CraftRenderer listItem, CraftRenderer list, int propertyId) {
    return listItem.hasProperty(propertyId)
        ? listItem.getProperty<Object>(propertyId)
        : list.getProperty<Object>(propertyId);
  }

  CraftRenderer? _createListSymbolRenderer(int index, CraftRenderer renderer) {
    Object? defaultListSymbol =
        getListItemOrListProperty(renderer, this, CraftProperty.LIST_SYMBOL);
    if (defaultListSymbol is CraftText) {
      return _surroundTextBullet(CraftTextRenderer(defaultListSymbol));
    } else if (defaultListSymbol is CraftListNumberingType) {
      CraftListNumberingType numberingType = defaultListSymbol;
      String numberText;
      switch (numberingType) {
        case CraftListNumberingType.DECIMAL:
          numberText = index.toString();
          break;
        case CraftListNumberingType.DECIMAL_LEADING_ZERO:
          numberText = (index < 10 ? "0" : "") + index.toString();
          break;
        case CraftListNumberingType.ROMAN_LOWER:
          numberText = CraftRomanNumbering.toRomanLowerCase(index);
          break;
        case CraftListNumberingType.ROMAN_UPPER:
          numberText = CraftRomanNumbering.toRomanUpperCase(index);
          break;
        case CraftListNumberingType.ENGLISH_LOWER:
          numberText =
              CraftEnglishAlphabetNumbering.toLatinAlphabetNumberLowerCase(
                  index);
          break;
        case CraftListNumberingType.ENGLISH_UPPER:
          numberText =
              CraftEnglishAlphabetNumbering.toLatinAlphabetNumberUpperCase(
                  index);
          break;
        case CraftListNumberingType.GREEK_LOWER:
          numberText = CraftGreekAlphabetNumbering.toGreekAlphabetNumber(
              index, false, true);
          break;
        case CraftListNumberingType.GREEK_UPPER:
          numberText = CraftGreekAlphabetNumbering.toGreekAlphabetNumber(
              index, true, true);
          break;
        case CraftListNumberingType.ZAPF_DINGBATS_1:
          numberText = String.fromCharCode(index + 171);
          break;
        case CraftListNumberingType.ZAPF_DINGBATS_2:
          numberText = String.fromCharCode(index + 181);
          break;
        case CraftListNumberingType.ZAPF_DINGBATS_3:
          numberText = String.fromCharCode(index + 191);
          break;
        case CraftListNumberingType.ZAPF_DINGBATS_4:
          numberText = String.fromCharCode(index + 201);
          break;
      }

      CraftText textElement = CraftText((getListItemOrListProperty(
                      renderer, this, CraftProperty.LIST_SYMBOL_PRE_TEXT)
                  as String? ??
              "") +
          numberText +
          (getListItemOrListProperty(
                      renderer, this, CraftProperty.LIST_SYMBOL_POST_TEXT)
                  as String? ??
              ""));

      const symbolFonts = {
        CraftListNumberingType.GREEK_LOWER: CraftStandardFonts.SYMBOL,
        CraftListNumberingType.GREEK_UPPER: CraftStandardFonts.SYMBOL,
        CraftListNumberingType.ZAPF_DINGBATS_1: CraftStandardFonts.ZAPFDINGBATS,
        CraftListNumberingType.ZAPF_DINGBATS_2: CraftStandardFonts.ZAPFDINGBATS,
        CraftListNumberingType.ZAPF_DINGBATS_3: CraftStandardFonts.ZAPFDINGBATS,
        CraftListNumberingType.ZAPF_DINGBATS_4: CraftStandardFonts.ZAPFDINGBATS,
      };
      final family = symbolFonts[numberingType];
      final CraftRenderer textRenderer = family == null
          ? CraftTextRenderer(textElement)
          : _ConstantFontTextRenderer(textElement, family);
      if (family != null) {
        // The renderer also retains the requested family for deferred creation.
        // Metric resources can be supplied separately by applications.
        try {
          textRenderer.setProperty(
              CraftProperty.FONT, CraftPdfFontFactory.createFont(family));
        } catch (_) {
          // Preserve deferred font resolution when a core-font resource is absent.
        }
      }
      return _surroundTextBullet(textRenderer);
    } else if (defaultListSymbol is CraftImage) {
      return defaultListSymbol.createRendererSubTree();
    }
    return null;
  }

  CraftLineRenderer _surroundTextBullet(CraftRenderer bulletRenderer) {
    CraftLineRenderer lineRenderer = CraftLineRenderer();
    CraftText zeroWidthJoiner = CraftText("\u200D");
    // zeroWidthJoiner.getAccessibilityProperties().setRole(StandardRoles.ARTIFACT);
    lineRenderer.addChild(CraftTextRenderer(zeroWidthJoiner));
    lineRenderer.addChild(bulletRenderer);
    lineRenderer.addChild(CraftTextRenderer(zeroWidthJoiner));
    return lineRenderer;
  }

  CraftLayoutResult _correctListSplitting(
      CraftRenderer splitRenderer,
      CraftRenderer? overflowRenderer,
      CraftRenderer causeOfNothing,
      CraftLayoutArea occupiedArea) {
    // the first not rendered child
    int firstNotRendered = splitRenderer
        .getChildRenderers()[0]
        .getChildRenderers()
        .indexOf(causeOfNothing);
    if (-1 == firstNotRendered) {
      return CraftLayoutResult(
          overflowRenderer == null
              ? CraftLayoutResult.FULL
              : CraftLayoutResult.PARTIAL,
          occupiedArea,
          splitRenderer,
          overflowRenderer,
          this);
    }

    // Notice that placed item is a son of the first ListItemRenderer (otherwise there would be now FORCED_PLACEMENT applied)
    CraftRenderer firstListItemRenderer = splitRenderer.getChildRenderers()[0];
    CraftListRenderer newOverflowRenderer =
        createOverflowRenderer(CraftLayoutResult.PARTIAL) as CraftListRenderer;
    newOverflowRenderer.deleteOwnProperty(CraftProperty.FORCED_PLACEMENT);

    // ListItemRenderer for not rendered children of firstListItemRenderer
    newOverflowRenderer.childRenderers.add(
        (firstListItemRenderer as CraftListItemRenderer)
            .createOverflowRenderer(CraftLayoutResult.PARTIAL));
    newOverflowRenderer.childRenderers
        .addAll(splitRenderer.getChildRenderers().sublist(1));

    List<CraftRenderer> childrenStillRemainingToRender =
        List<CraftRenderer>.from(firstListItemRenderer
            .getChildRenderers()
            .sublist(firstNotRendered + 1));

    // 'this' renderer will become split renderer
    splitRenderer
        .getChildRenderers()
        .removeRange(1, splitRenderer.getChildRenderers().length);

    if (childrenStillRemainingToRender.isNotEmpty) {
      newOverflowRenderer
          .getChildRenderers()[0]
          .getChildRenderers()
          .addAll(childrenStillRemainingToRender);
      splitRenderer.getChildRenderers()[0].getChildRenderers().removeRange(
          firstNotRendered + 1,
          splitRenderer.getChildRenderers()[0].getChildRenderers().length);
      newOverflowRenderer.getChildRenderers()[0].setProperty(
          CraftProperty.MARGIN_LEFT,
          splitRenderer
              .getChildRenderers()[0]
              .getProperty<CraftUnitValue>(CraftProperty.MARGIN_LEFT));
    } else {
      newOverflowRenderer.childRenderers.removeAt(0);
    }

    if (overflowRenderer != null) {
      newOverflowRenderer.childRenderers
          .addAll(overflowRenderer.getChildRenderers());
    }

    if (newOverflowRenderer.childRenderers.isNotEmpty) {
      return CraftLayoutResult(CraftLayoutResult.PARTIAL, occupiedArea,
          splitRenderer, newOverflowRenderer, this);
    } else {
      return CraftLayoutResult(
          CraftLayoutResult.FULL, occupiedArea, null, null, this);
    }
  }

  CraftLayoutResult? _initializeListSymbols(CraftLayoutContext layoutContext) {
    if (!hasOwnProperty(CraftProperty.LIST_SYMBOLS_INITIALIZED)) {
      List<CraftRenderer?> symbolRenderers = <CraftRenderer?>[];
      int listItemNum = getProperty<int>(CraftProperty.LIST_START) ?? 1;

      for (CraftRenderer renderer in childRenderers) {
        renderer.setParent(this);
        var ordinal =
            renderer.getProperty<int?>(CraftProperty.LIST_SYMBOL_ORDINAL_VALUE);
        if (ordinal != null) {
          listItemNum = ordinal;
        }

        CraftRenderer? currentSymbolRenderer =
            makeListSymbolRenderer(listItemNum, renderer);
        // RTL check omitted for now

        CraftLayoutResult? listSymbolLayoutResult;
        if (currentSymbolRenderer != null) {
          listItemNum++;
          currentSymbolRenderer.setParent(renderer);
          listSymbolLayoutResult = currentSymbolRenderer.layout(layoutContext);
          currentSymbolRenderer.setParent(null);
        }

        bool isForcedPlacement =
            true == getPropertyAsBoolean(CraftProperty.FORCED_PLACEMENT);
        bool listSymbolNotFit = listSymbolLayoutResult != null &&
            listSymbolLayoutResult.getStatus() != CraftLayoutResult.FULL;

        if (listSymbolNotFit && isForcedPlacement) {
          currentSymbolRenderer = null;
        }

        symbolRenderers.add(currentSymbolRenderer);

        if (listSymbolNotFit && !isForcedPlacement) {
          return CraftLayoutResult(CraftLayoutResult.NOTHING, null, null, this,
              listSymbolLayoutResult.getCauseOfNothing() ?? this);
        }
      }

      double maxSymbolWidth = 0;
      for (int i = 0; i < childRenderers.length; i++) {
        CraftRenderer? symbolRenderer = symbolRenderers[i];
        if (symbolRenderer != null) {
          CraftRenderer listItemRenderer = childRenderers[i];
          if (getListItemOrListProperty(
                  listItemRenderer, this, CraftProperty.LIST_SYMBOL_POSITION) !=
              CraftListSymbolPosition.INSIDE) {
            maxSymbolWidth = math.max(maxSymbolWidth,
                symbolRenderer.getOccupiedArea()?.getBBox().getWidth() ?? 0);
          }
        }
      }

      double? symbolIndent =
          getProperty<double?>(CraftProperty.LIST_SYMBOL_INDENT);
      int index = 0;
      for (CraftRenderer childRenderer in childRenderers) {
        // RTL margins logic omitted for simplicity
        int marginToSet = CraftProperty.MARGIN_LEFT;
        childRenderer.deleteOwnProperty(marginToSet);
        CraftUnitValue marginToSetUV =
            childRenderer.getProperty<CraftUnitValue>(marginToSet) ??
                CraftUnitValue.createPointValue(0.0);

        double calculatedMargin = marginToSetUV.getValue();
        if (getListItemOrListProperty(
                childRenderer, this, CraftProperty.LIST_SYMBOL_POSITION) ==
            CraftListSymbolPosition.DEFAULT) {
          calculatedMargin += maxSymbolWidth + (symbolIndent ?? 0.0);
        }

        childRenderer.setProperty(
            marginToSet, CraftUnitValue.createPointValue(calculatedMargin));
        CraftRenderer? symbolRenderer = symbolRenderers[index++];
        if (childRenderer is CraftListItemRenderer) {
          childRenderer.addSymbolRenderer(symbolRenderer, maxSymbolWidth);
        }
      }
      setProperty(CraftProperty.LIST_SYMBOLS_INITIALIZED, true);
    }
    return null;
  }
}

class _ConstantFontTextRenderer extends CraftTextRenderer {
  final String constantFontName;

  _ConstantFontTextRenderer(CraftText textElement, this.constantFontName)
      : super(textElement);

  @override
  Future<void> draw(CraftDrawContext drawContext) async {
    try {
      setProperty(
          CraftProperty.FONT, CraftPdfFontFactory.createFont(constantFontName));
    } catch (e) {
      // Ignore
    }
    await super.draw(drawContext);
  }
}
