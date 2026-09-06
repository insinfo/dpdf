import 'package:pdfcraft/src/layout/element/div.dart';
import 'package:pdfcraft/src/layout/element/paragraph.dart';
import 'package:pdfcraft/src/layout/element/text.dart';
import 'package:pdfcraft/src/layout/properties/property.dart';
import 'package:pdfcraft/src/layout/properties/list_numbering_type.dart';
import 'package:pdfcraft/src/layout/properties/list_symbol_position.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';
import 'package:pdfcraft/src/layout/renderer/list_item_renderer.dart';

class CraftListItem extends CraftDiv {
  CraftListItem([dynamic content]) : super() {
    if (content is String) {
      add(CraftParagraph(content).setMarginTop(0).setMarginBottom(0));
    } else if (content != null) {
      add(content);
    }
  }

  CraftListItem setListSymbolOrdinalValue(int ordinalValue) {
    setProperty(CraftProperty.LIST_SYMBOL_ORDINAL_VALUE, ordinalValue);
    return this;
  }

  @override
  T? getDefaultProperty<T>(int property) {
    switch (property) {
      case CraftProperty.LIST_SYMBOL_POSITION:
        return CraftListSymbolPosition.DEFAULT as T;
      default:
        return super.getDefaultProperty<T>(property);
    }
  }

  CraftListItem setListSymbol(dynamic symbol) {
    if (symbol is String) {
      setProperty(CraftProperty.LIST_SYMBOL, CraftText(symbol));
    } else if (symbol is CraftText || symbol is CraftListNumberingType) {
      // TODO: Image support
      if (symbol is CraftListNumberingType) {
        if (symbol == CraftListNumberingType.ZAPF_DINGBATS_1 ||
            symbol == CraftListNumberingType.ZAPF_DINGBATS_2 ||
            symbol == CraftListNumberingType.ZAPF_DINGBATS_3 ||
            symbol == CraftListNumberingType.ZAPF_DINGBATS_4) {
          setProperty(CraftProperty.LIST_SYMBOL_POST_TEXT, " ");
        }
      }
      setProperty(CraftProperty.LIST_SYMBOL, symbol);
    }
    return this;
  }

  @override
  CraftRenderer makeNewRenderer() {
    return CraftListItemRenderer(this);
  }
}
