import 'package:dpdf/src/layout/renderer/div_renderer.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/element/list_item.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/properties/list_symbol_position.dart';
import 'package:dpdf/src/layout/renderer/list_renderer.dart';
import 'package:dpdf/src/layout/properties/list_symbol_alignment.dart';
import 'package:dpdf/src/layout/renderer/line_renderer.dart';
import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/renderer/paragraph_renderer.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';

class ListItemRenderer extends DivRenderer {
  IRenderer? symbolRenderer;
  double symbolAreaWidth = 0;
  bool symbolAddedInside = false;

  ListItemRenderer(ListItem modelElement) : super(modelElement);

  void addSymbolRenderer(IRenderer? symbolRenderer, double symbolAreaWidth) {
    this.symbolRenderer = symbolRenderer;
    this.symbolAreaWidth = symbolAreaWidth;
  }

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    _applyListSymbolPosition();
    LayoutResult? result = super.layout(layoutContext);
    return result;
  }

  @override
  Future<void> draw(DrawContext drawContext) async {
    if (occupiedArea == null) return;
    await super.draw(drawContext);

    if (symbolRenderer != null && !symbolAddedInside) {
      symbolRenderer!.setParent(this);
      double x = occupiedArea!.getBBox().getLeft();

      ListSymbolPosition symbolPosition =
          (ListRenderer.getListItemOrListProperty(
                      this, parent!, Property.LIST_SYMBOL_POSITION)
                  as ListSymbolPosition?) ??
              ListSymbolPosition.DEFAULT;

      if (symbolPosition != ListSymbolPosition.DEFAULT) {
        double? symbolIndent =
            getProperty<double?>(Property.LIST_SYMBOL_INDENT);
        x -= (symbolAreaWidth + (symbolIndent ?? 0.0));
      }

      // Basic vertical alignment of symbol with first line of content
      if (childRenderers.isNotEmpty) {
        double? yLine;
        for (var child in childRenderers) {
          if ((child.getOccupiedArea()?.getBBox().getHeight() ?? 0) > 0) {
            yLine = (child as AbstractRenderer).getFirstYLineRecursively();
            if (yLine != null) break;
          }
        }

        if (yLine != null) {
          if (symbolRenderer is LineRenderer) {
            symbolRenderer!
                .move(0, yLine - (symbolRenderer as LineRenderer).getYLine());
          } else {
            symbolRenderer!.move(
                0,
                yLine -
                    (symbolRenderer!.getOccupiedArea()?.getBBox().getBottom() ??
                        0));
          }
        }
      }

      ListSymbolAlignment listSymbolAlignment =
          (parent?.getProperty<ListSymbolAlignment?>(
                  Property.LIST_SYMBOL_ALIGNMENT) ??
              ListSymbolAlignment.RIGHT);
      double dxPosition =
          x - (symbolRenderer!.getOccupiedArea()?.getBBox().getLeft() ?? 0);

      if (listSymbolAlignment == ListSymbolAlignment.RIGHT) {
        dxPosition += symbolAreaWidth -
            (symbolRenderer!.getOccupiedArea()?.getBBox().getWidth() ?? 0);
      }

      symbolRenderer!.move(dxPosition, 0);
      await symbolRenderer!.draw(drawContext);
    }
  }

  @override
  IRenderer getNextRenderer() {
    return ListItemRenderer(modelElement as ListItem);
  }

  void _applyListSymbolPosition() {
    if (symbolRenderer == null) return;
    ListSymbolPosition symbolPosition = (ListRenderer.getListItemOrListProperty(
                this, parent!, Property.LIST_SYMBOL_POSITION)
            as ListSymbolPosition?) ??
        ListSymbolPosition.DEFAULT;

    if (symbolPosition == ListSymbolPosition.INSIDE) {
      if (childRenderers.isNotEmpty && childRenderers[0] is ParagraphRenderer) {
        _injectSymbolRendererIntoParagraphRenderer(
            childRenderers[0] as ParagraphRenderer);
        symbolAddedInside = true;
      }
      if (!symbolAddedInside) {
        IRenderer paragraphRenderer = _renderSymbolInNeutralParagraph();
        childRenderers.insert(0, paragraphRenderer);
        symbolAddedInside = true;
      }
    }
  }

  void _injectSymbolRendererIntoParagraphRenderer(
      ParagraphRenderer paragraphRenderer) {
    double? symbolIndent = getProperty<double?>(Property.LIST_SYMBOL_INDENT);
    if (symbolRenderer is LineRenderer) {
      if (symbolIndent != null) {
        symbolRenderer!.getChildRenderers()[1].setProperty(
            Property.MARGIN_RIGHT, UnitValue.createPointValue(symbolIndent));
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
        symbolRenderer!.setProperty(
            Property.MARGIN_RIGHT, UnitValue.createPointValue(symbolIndent));
      }
      paragraphRenderer.getChildRenderers().insert(0, symbolRenderer!);
      symbolRenderer!.setParent(paragraphRenderer);
    }
  }

  IRenderer _renderSymbolInNeutralParagraph() {
    Paragraph p = Paragraph();
    IRenderer paragraphRenderer = p.setMargin(0.0).createRendererSubTree()!;
    _injectSymbolRendererIntoParagraphRenderer(
        paragraphRenderer as ParagraphRenderer);
    return paragraphRenderer;
  }
}
