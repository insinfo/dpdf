import 'package:pdfcraft/src/layout/element/block_element.dart';
import 'package:pdfcraft/src/layout/element/list_item.dart';
import 'package:pdfcraft/src/layout/element/text.dart';
import 'package:pdfcraft/src/layout/properties/property.dart';
import 'package:pdfcraft/src/layout/properties/list_numbering_type.dart';
import 'package:pdfcraft/src/layout/properties/list_symbol_alignment.dart';
import 'package:pdfcraft/src/layout/properties/list_symbol_position.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';
import 'package:pdfcraft/src/layout/renderer/list_renderer.dart';
import 'package:pdfcraft/src/layout/element/image.dart';
import 'package:pdfcraft/src/kernel/pdf/tagutils/accessibility_properties.dart';

class CraftList extends CraftBlockElement<CraftList> {
  static const String DEFAULT_LIST_SYMBOL = "- ";

  @override
  CraftAccessibilityProperties getAccessibilityProperties() {
    return CraftAccessibilityProperties();
  }

  CraftList([CraftListNumberingType? numberingType]) : super() {
    if (numberingType != null) {
      setListSymbol(numberingType);
    }
  }

  @override
  T? getDefaultProperty<T>(int property) {
    switch (property) {
      case CraftProperty.LIST_SYMBOL:
        return CraftText(DEFAULT_LIST_SYMBOL) as T;
      case CraftProperty.LIST_SYMBOL_PRE_TEXT:
        return "" as T;
      case CraftProperty.LIST_SYMBOL_POST_TEXT:
        return ". " as T;
      case CraftProperty.LIST_SYMBOL_POSITION:
        return CraftListSymbolPosition.DEFAULT as T;
      default:
        return super.getDefaultProperty<T>(property);
    }
  }

  CraftList add(dynamic item) {
    if (item is CraftListItem) {
      childElements.add(item);
    } else if (item is String) {
      childElements.add(CraftListItem(item));
    } else if (item != null) {
      //  allows adding other things to List?
      // List.cs Add(ListItem) is the main one.
      // Add(String) creates a ListItem.
      childElements.add(item);
    }
    return this;
  }

  CraftList setItemStartIndex(int start) {
    setProperty(CraftProperty.LIST_START, start);
    return this;
  }

  CraftList setListSymbol(dynamic symbol) {
    if (symbol is String) {
      setProperty(CraftProperty.LIST_SYMBOL, CraftText(symbol));
    } else if (symbol is CraftText ||
        symbol is CraftListNumberingType ||
        symbol is CraftImage) {
      if (symbol is CraftListNumberingType) {
        if (symbol == CraftListNumberingType.ZAPF_DINGBATS_1 ||
            symbol == CraftListNumberingType.ZAPF_DINGBATS_2 ||
            symbol == CraftListNumberingType.ZAPF_DINGBATS_3 ||
            symbol == CraftListNumberingType.ZAPF_DINGBATS_4) {
          setPostSymbolText(" ");
        }
      }
      setProperty(CraftProperty.LIST_SYMBOL, symbol);
    }
    return this;
  }

  CraftList setListSymbolAlignment(CraftListSymbolAlignment alignment) {
    setProperty(CraftProperty.LIST_SYMBOL_ALIGNMENT, alignment);
    return this;
  }

  double? getSymbolIndent() {
    return getProperty<double?>(CraftProperty.LIST_SYMBOL_INDENT);
  }

  CraftList setSymbolIndent(double symbolIndent) {
    setProperty(CraftProperty.LIST_SYMBOL_INDENT, symbolIndent);
    return this;
  }

  String? getPostSymbolText() {
    return getProperty<String?>(CraftProperty.LIST_SYMBOL_POST_TEXT);
  }

  void setPostSymbolText(String postSymbolText) {
    setProperty(CraftProperty.LIST_SYMBOL_POST_TEXT, postSymbolText);
  }

  String? getPreSymbolText() {
    return getProperty<String?>(CraftProperty.LIST_SYMBOL_PRE_TEXT);
  }

  void setPreSymbolText(String preSymbolText) {
    setProperty(CraftProperty.LIST_SYMBOL_PRE_TEXT, preSymbolText);
  }

  @override
  CraftRenderer makeNewRenderer() {
    return CraftListRenderer(this);
  }
}
