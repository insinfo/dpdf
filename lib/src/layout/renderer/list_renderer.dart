import 'dart:math' as math;

import 'package:dpdf/src/io/font/constants/standard_fonts.dart';
import 'package:dpdf/src/kernel/font/pdf_font_factory.dart';
import 'package:dpdf/src/kernel/numbering/english_alphabet_numbering.dart';
import 'package:dpdf/src/kernel/numbering/greek_alphabet_numbering.dart';
import 'package:dpdf/src/kernel/numbering/roman_numbering.dart';
import 'package:dpdf/src/layout/element/list.dart' as elements;
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/element/image.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/properties/list_numbering_type.dart';
import 'package:dpdf/src/layout/properties/list_symbol_position.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/renderer/block_renderer.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/renderer/line_renderer.dart';
import 'package:dpdf/src/layout/renderer/list_item_renderer.dart';
import 'package:dpdf/src/layout/renderer/text_renderer.dart';

class ListRenderer extends BlockRenderer {
  ListRenderer(elements.PdfList super.modelElement);

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    LayoutResult? errorResult = _initializeListSymbols(layoutContext);
    if (errorResult != null) {
      return errorResult;
    }
    LayoutResult? result = super.layout(layoutContext);
    if (result == null) return null;

    // cannot place even the first ListItemRenderer
    if (true == getPropertyAsBoolean(Property.FORCED_PLACEMENT) &&
        result.getCauseOfNothing() != null) {
      if (LayoutResult.FULL == result.getStatus()) {
        result = _correctListSplitting(
            this, null, result.getCauseOfNothing()!, result.getOccupiedArea()!);
      } else if (LayoutResult.PARTIAL == result.getStatus()) {
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
  Renderer getNextRenderer() {
    return ListRenderer(modelElement as elements.PdfList);
  }

  @override
  AbstractRenderer createSplitRenderer(int layoutResult) {
    AbstractRenderer splitRenderer = super.createSplitRenderer(layoutResult);
    splitRenderer.addAllProperties(getOwnProperties());
    splitRenderer.setProperty(Property.LIST_SYMBOLS_INITIALIZED, true);
    return splitRenderer;
  }

  @override
  AbstractRenderer createOverflowRenderer(int layoutResult) {
    AbstractRenderer overflowRenderer =
        super.createOverflowRenderer(layoutResult);
    overflowRenderer.addAllProperties(getOwnProperties());
    overflowRenderer.setProperty(Property.LIST_SYMBOLS_INITIALIZED, true);
    return overflowRenderer;
  }

  Renderer? makeListSymbolRenderer(int index, Renderer renderer) {
    Renderer? symbolRenderer = _createListSymbolRenderer(index, renderer);
    if (symbolRenderer != null) {
      symbolRenderer.setProperty(Property.UNDERLINE, false);
    }
    return symbolRenderer;
  }

  static Object? getListItemOrListProperty(
      Renderer listItem, Renderer list, int propertyId) {
    return listItem.hasProperty(propertyId)
        ? listItem.getProperty<Object>(propertyId)
        : list.getProperty<Object>(propertyId);
  }

  Renderer? _createListSymbolRenderer(int index, Renderer renderer) {
    Object? defaultListSymbol =
        getListItemOrListProperty(renderer, this, Property.LIST_SYMBOL);
    if (defaultListSymbol is Text) {
      return _surroundTextBullet(TextRenderer(defaultListSymbol));
    } else if (defaultListSymbol is ListNumberingType) {
      ListNumberingType numberingType = defaultListSymbol;
      String numberText;
      switch (numberingType) {
        case ListNumberingType.DECIMAL:
          numberText = index.toString();
          break;
        case ListNumberingType.DECIMAL_LEADING_ZERO:
          numberText = (index < 10 ? "0" : "") + index.toString();
          break;
        case ListNumberingType.ROMAN_LOWER:
          numberText = RomanNumbering.toRomanLowerCase(index);
          break;
        case ListNumberingType.ROMAN_UPPER:
          numberText = RomanNumbering.toRomanUpperCase(index);
          break;
        case ListNumberingType.ENGLISH_LOWER:
          numberText =
              EnglishAlphabetNumbering.toLatinAlphabetNumberLowerCase(index);
          break;
        case ListNumberingType.ENGLISH_UPPER:
          numberText =
              EnglishAlphabetNumbering.toLatinAlphabetNumberUpperCase(index);
          break;
        case ListNumberingType.GREEK_LOWER:
          numberText =
              GreekAlphabetNumbering.toGreekAlphabetNumber(index, false, true);
          break;
        case ListNumberingType.GREEK_UPPER:
          numberText =
              GreekAlphabetNumbering.toGreekAlphabetNumber(index, true, true);
          break;
        case ListNumberingType.ZAPF_DINGBATS_1:
          numberText = String.fromCharCode(index + 171);
          break;
        case ListNumberingType.ZAPF_DINGBATS_2:
          numberText = String.fromCharCode(index + 181);
          break;
        case ListNumberingType.ZAPF_DINGBATS_3:
          numberText = String.fromCharCode(index + 191);
          break;
        case ListNumberingType.ZAPF_DINGBATS_4:
          numberText = String.fromCharCode(index + 201);
          break;
      }

      Text textElement = Text((getListItemOrListProperty(
                  renderer, this, Property.LIST_SYMBOL_PRE_TEXT) as String? ??
              "") +
          numberText +
          (getListItemOrListProperty(
                  renderer, this, Property.LIST_SYMBOL_POST_TEXT) as String? ??
              ""));

      const symbolFonts = {
        ListNumberingType.GREEK_LOWER: StandardFonts.SYMBOL,
        ListNumberingType.GREEK_UPPER: StandardFonts.SYMBOL,
        ListNumberingType.ZAPF_DINGBATS_1: StandardFonts.ZAPFDINGBATS,
        ListNumberingType.ZAPF_DINGBATS_2: StandardFonts.ZAPFDINGBATS,
        ListNumberingType.ZAPF_DINGBATS_3: StandardFonts.ZAPFDINGBATS,
        ListNumberingType.ZAPF_DINGBATS_4: StandardFonts.ZAPFDINGBATS,
      };
      final family = symbolFonts[numberingType];
      final Renderer textRenderer = family == null
          ? TextRenderer(textElement)
          : _ConstantFontTextRenderer(textElement, family);
      if (family != null) {
        // The renderer also retains the requested family for deferred creation.
        // Metric resources can be supplied separately by applications.
        try {
          textRenderer.setProperty(
              Property.FONT, PdfFontFactory.createFont(family));
        } catch (_) {
          // Preserve deferred font resolution when a core-font resource is absent.
        }
      }
      return _surroundTextBullet(textRenderer);
    } else if (defaultListSymbol is Image) {
      return defaultListSymbol.createRendererSubTree();
    }
    return null;
  }

  LineRenderer _surroundTextBullet(Renderer bulletRenderer) {
    LineRenderer lineRenderer = LineRenderer();
    Text zeroWidthJoiner = Text("\u200D");
    // zeroWidthJoiner.getAccessibilityProperties().setRole(StandardRoles.ARTIFACT);
    lineRenderer.addChild(TextRenderer(zeroWidthJoiner));
    lineRenderer.addChild(bulletRenderer);
    lineRenderer.addChild(TextRenderer(zeroWidthJoiner));
    return lineRenderer;
  }

  LayoutResult _correctListSplitting(
      Renderer splitRenderer,
      Renderer? overflowRenderer,
      Renderer causeOfNothing,
      LayoutArea occupiedArea) {
    // the first not rendered child
    int firstNotRendered = splitRenderer
        .getChildRenderers()[0]
        .getChildRenderers()
        .indexOf(causeOfNothing);
    if (-1 == firstNotRendered) {
      return LayoutResult(
          overflowRenderer == null ? LayoutResult.FULL : LayoutResult.PARTIAL,
          occupiedArea,
          splitRenderer,
          overflowRenderer,
          this);
    }

    // Notice that placed item is a son of the first ListItemRenderer (otherwise there would be now FORCED_PLACEMENT applied)
    Renderer firstListItemRenderer = splitRenderer.getChildRenderers()[0];
    ListRenderer newOverflowRenderer =
        createOverflowRenderer(LayoutResult.PARTIAL) as ListRenderer;
    newOverflowRenderer.deleteOwnProperty(Property.FORCED_PLACEMENT);

    // ListItemRenderer for not rendered children of firstListItemRenderer
    newOverflowRenderer.childRenderers.add(
        (firstListItemRenderer as ListItemRenderer)
            .createOverflowRenderer(LayoutResult.PARTIAL));
    newOverflowRenderer.childRenderers
        .addAll(splitRenderer.getChildRenderers().sublist(1));

    List<Renderer> childrenStillRemainingToRender = List<Renderer>.from(
        firstListItemRenderer
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
          Property.MARGIN_LEFT,
          splitRenderer
              .getChildRenderers()[0]
              .getProperty<UnitValue>(Property.MARGIN_LEFT));
    } else {
      newOverflowRenderer.childRenderers.removeAt(0);
    }

    if (overflowRenderer != null) {
      newOverflowRenderer.childRenderers
          .addAll(overflowRenderer.getChildRenderers());
    }

    if (newOverflowRenderer.childRenderers.isNotEmpty) {
      return LayoutResult(LayoutResult.PARTIAL, occupiedArea, splitRenderer,
          newOverflowRenderer, this);
    } else {
      return LayoutResult(LayoutResult.FULL, occupiedArea, null, null, this);
    }
  }

  LayoutResult? _initializeListSymbols(LayoutContext layoutContext) {
    if (!hasOwnProperty(Property.LIST_SYMBOLS_INITIALIZED)) {
      List<Renderer?> symbolRenderers = <Renderer?>[];
      int listItemNum = getProperty<int>(Property.LIST_START) ?? 1;

      for (Renderer renderer in childRenderers) {
        renderer.setParent(this);
        var ordinal =
            renderer.getProperty<int?>(Property.LIST_SYMBOL_ORDINAL_VALUE);
        if (ordinal != null) {
          listItemNum = ordinal;
        }

        Renderer? currentSymbolRenderer =
            makeListSymbolRenderer(listItemNum, renderer);
        // RTL check omitted for now

        LayoutResult? listSymbolLayoutResult;
        if (currentSymbolRenderer != null) {
          listItemNum++;
          currentSymbolRenderer.setParent(renderer);
          listSymbolLayoutResult = currentSymbolRenderer.layout(layoutContext);
          currentSymbolRenderer.setParent(null);
        }

        bool isForcedPlacement =
            true == getPropertyAsBoolean(Property.FORCED_PLACEMENT);
        bool listSymbolNotFit = listSymbolLayoutResult != null &&
            listSymbolLayoutResult.getStatus() != LayoutResult.FULL;

        if (listSymbolNotFit && isForcedPlacement) {
          currentSymbolRenderer = null;
        }

        symbolRenderers.add(currentSymbolRenderer);

        if (listSymbolNotFit && !isForcedPlacement) {
          return LayoutResult(LayoutResult.NOTHING, null, null, this,
              listSymbolLayoutResult.getCauseOfNothing() ?? this);
        }
      }

      double maxSymbolWidth = 0;
      for (int i = 0; i < childRenderers.length; i++) {
        Renderer? symbolRenderer = symbolRenderers[i];
        if (symbolRenderer != null) {
          Renderer listItemRenderer = childRenderers[i];
          if (getListItemOrListProperty(
                  listItemRenderer, this, Property.LIST_SYMBOL_POSITION) !=
              ListSymbolPosition.INSIDE) {
            maxSymbolWidth = math.max(maxSymbolWidth,
                symbolRenderer.getOccupiedArea()?.getBBox().getWidth() ?? 0);
          }
        }
      }

      double? symbolIndent = getProperty<double?>(Property.LIST_SYMBOL_INDENT);
      int index = 0;
      for (Renderer childRenderer in childRenderers) {
        // RTL margins logic omitted for simplicity
        int marginToSet = Property.MARGIN_LEFT;
        childRenderer.deleteOwnProperty(marginToSet);
        UnitValue marginToSetUV =
            childRenderer.getProperty<UnitValue>(marginToSet) ??
                UnitValue.createPointValue(0.0);

        double calculatedMargin = marginToSetUV.getValue();
        if (getListItemOrListProperty(
                childRenderer, this, Property.LIST_SYMBOL_POSITION) ==
            ListSymbolPosition.DEFAULT) {
          calculatedMargin += maxSymbolWidth + (symbolIndent ?? 0.0);
        }

        childRenderer.setProperty(
            marginToSet, UnitValue.createPointValue(calculatedMargin));
        Renderer? symbolRenderer = symbolRenderers[index++];
        if (childRenderer is ListItemRenderer) {
          childRenderer.addSymbolRenderer(symbolRenderer, maxSymbolWidth);
        }
      }
      setProperty(Property.LIST_SYMBOLS_INITIALIZED, true);
    }
    return null;
  }
}

class _ConstantFontTextRenderer extends TextRenderer {
  final String constantFontName;

  _ConstantFontTextRenderer(super.textElement, this.constantFontName);

  @override
  Future<void> draw(DrawContext drawContext) async {
    try {
      setProperty(Property.FONT, PdfFontFactory.createFont(constantFontName));
    } catch (e) {
      // Ignore
    }
    await super.draw(drawContext);
  }
}
