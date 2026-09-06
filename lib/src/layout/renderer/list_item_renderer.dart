import 'package:pdfcraft/src/layout/renderer/div_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';
import 'package:pdfcraft/src/layout/layout/layout_context.dart';
import 'package:pdfcraft/src/layout/layout/layout_result.dart';
import 'package:pdfcraft/src/layout/properties/property.dart';
import 'package:pdfcraft/src/layout/element/list_item.dart';
import 'package:pdfcraft/src/layout/renderer/draw_context.dart';
import 'package:pdfcraft/src/layout/properties/list_symbol_position.dart';
import 'package:pdfcraft/src/layout/renderer/list_renderer.dart';
import 'package:pdfcraft/src/layout/properties/list_symbol_alignment.dart';
import 'package:pdfcraft/src/layout/renderer/line_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/abstract_renderer.dart';
import 'package:pdfcraft/src/layout/properties/unit_value.dart';
import 'package:pdfcraft/src/layout/renderer/paragraph_renderer.dart';
import 'package:pdfcraft/src/layout/element/paragraph.dart';

class CraftListItemRenderer extends CraftDivRenderer {
  CraftRenderer? symbolRenderer;
  double symbolAreaWidth = 0;
  bool symbolAddedInside = false;

  CraftListItemRenderer(CraftListItem modelElement) : super(modelElement);

  void addSymbolRenderer(
      CraftRenderer? symbolRenderer, double symbolAreaWidth) {
    this.symbolRenderer = symbolRenderer;
    this.symbolAreaWidth = symbolAreaWidth;
  }

  @override
  CraftLayoutResult? layout(CraftLayoutContext layoutContext) {
    _applyListSymbolPosition();
    CraftLayoutResult? result = super.layout(layoutContext);
    return result;
  }

  @override
  Future<void> draw(CraftDrawContext drawContext) async {
    if (occupiedArea == null) return;
    await super.draw(drawContext);

    if (symbolRenderer != null && !symbolAddedInside) {
      symbolRenderer!.setParent(this);
      double x = occupiedArea!.getBBox().getLeft();

      CraftListSymbolPosition symbolPosition =
          (CraftListRenderer.getListItemOrListProperty(
                      this, parent!, CraftProperty.LIST_SYMBOL_POSITION)
                  as CraftListSymbolPosition?) ??
              CraftListSymbolPosition.DEFAULT;

      if (symbolPosition != CraftListSymbolPosition.DEFAULT) {
        double? symbolIndent =
            getProperty<double?>(CraftProperty.LIST_SYMBOL_INDENT);
        x -= (symbolAreaWidth + (symbolIndent ?? 0.0));
      }

      // Basic vertical alignment of symbol with first line of content
      if (childRenderers.isNotEmpty) {
        double? yLine;
        for (var child in childRenderers) {
          if ((child.getOccupiedArea()?.getBBox().getHeight() ?? 0) > 0) {
            yLine = (child as CraftAbstractRenderer).getFirstYLineRecursively();
            if (yLine != null) break;
          }
        }

        if (yLine != null) {
          if (symbolRenderer is CraftLineRenderer) {
            symbolRenderer!.move(
                0, yLine - (symbolRenderer as CraftLineRenderer).getYLine());
          } else {
            symbolRenderer!.move(
                0,
                yLine -
                    (symbolRenderer!.getOccupiedArea()?.getBBox().getBottom() ??
                        0));
          }
        }
      }

      CraftListSymbolAlignment listSymbolAlignment =
          (parent?.getProperty<CraftListSymbolAlignment?>(
                  CraftProperty.LIST_SYMBOL_ALIGNMENT) ??
              CraftListSymbolAlignment.RIGHT);
      double dxPosition =
          x - (symbolRenderer!.getOccupiedArea()?.getBBox().getLeft() ?? 0);

      if (listSymbolAlignment == CraftListSymbolAlignment.RIGHT) {
        dxPosition += symbolAreaWidth -
            (symbolRenderer!.getOccupiedArea()?.getBBox().getWidth() ?? 0);
      }

      symbolRenderer!.move(dxPosition, 0);
      await symbolRenderer!.draw(drawContext);
    }
  }

  @override
  CraftRenderer getNextRenderer() {
    return CraftListItemRenderer(modelElement as CraftListItem);
  }

  void _applyListSymbolPosition() {
    if (symbolRenderer == null) return;
    CraftListSymbolPosition symbolPosition =
        (CraftListRenderer.getListItemOrListProperty(
                    this, parent!, CraftProperty.LIST_SYMBOL_POSITION)
                as CraftListSymbolPosition?) ??
            CraftListSymbolPosition.DEFAULT;

    if (symbolPosition == CraftListSymbolPosition.INSIDE) {
      if (childRenderers.isNotEmpty &&
          childRenderers[0] is CraftParagraphRenderer) {
        _injectSymbolRendererIntoParagraphRenderer(
            childRenderers[0] as CraftParagraphRenderer);
        symbolAddedInside = true;
      }
      if (!symbolAddedInside) {
        CraftRenderer paragraphRenderer = _renderSymbolInNeutralParagraph();
        childRenderers.insert(0, paragraphRenderer);
        symbolAddedInside = true;
      }
    }
  }

  void _injectSymbolRendererIntoParagraphRenderer(
      CraftParagraphRenderer paragraphRenderer) {
    double? symbolIndent =
        getProperty<double?>(CraftProperty.LIST_SYMBOL_INDENT);
    if (symbolRenderer is CraftLineRenderer) {
      if (symbolIndent != null) {
        symbolRenderer!.getChildRenderers()[1].setProperty(
            CraftProperty.MARGIN_RIGHT,
            CraftUnitValue.createPointValue(symbolIndent));
      }
      for (int i = symbolRenderer!.getChildRenderers().length - 1;
          i >= 0;
          i--) {
        paragraphRenderer
            .getChildRenderers()
            .insert(0, symbolRenderer!.getChildRenderers()[i]);
        symbolRenderer!.getChildRenderers()[i].setParent(paragraphRenderer);
      }
    } else {
      if (symbolIndent != null) {
        symbolRenderer!.setProperty(CraftProperty.MARGIN_RIGHT,
            CraftUnitValue.createPointValue(symbolIndent));
      }
      paragraphRenderer.getChildRenderers().insert(0, symbolRenderer!);
      symbolRenderer!.setParent(paragraphRenderer);
    }
  }

  CraftRenderer _renderSymbolInNeutralParagraph() {
    CraftParagraph p = CraftParagraph();
    CraftRenderer paragraphRenderer = p.setMargin(0.0).createRendererSubTree()!;
    _injectSymbolRendererIntoParagraphRenderer(
        paragraphRenderer as CraftParagraphRenderer);
    return paragraphRenderer;
  }
}
