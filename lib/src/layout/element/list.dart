import 'package:dpdf/src/layout/element/block_element.dart';
import 'package:dpdf/src/layout/element/list_item.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/list_numbering_type.dart';
import 'package:dpdf/src/layout/properties/list_symbol_alignment.dart';
import 'package:dpdf/src/layout/properties/list_symbol_position.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/renderer/list_renderer.dart';
import 'package:dpdf/src/layout/element/image.dart';
import 'package:dpdf/src/kernel/pdf/tagutils/accessibility_properties.dart';

class List extends BlockElement<List> {
  static const String DEFAULT_LIST_SYMBOL = "- ";

  @override
  AccessibilityProperties getAccessibilityProperties() {
    return AccessibilityProperties();
  }

  List([ListNumberingType? numberingType]) : super() {
    if (numberingType != null) {
      setListSymbol(numberingType);
    }
  }

  @override
  T? getDefaultProperty<T>(int property) {
    switch (property) {
      case Property.LIST_SYMBOL:
        return Text(DEFAULT_LIST_SYMBOL) as T;
      case Property.LIST_SYMBOL_PRE_TEXT:
        return "" as T;
      case Property.LIST_SYMBOL_POST_TEXT:
        return ". " as T;
      case Property.LIST_SYMBOL_POSITION:
        return ListSymbolPosition.DEFAULT as T;
      default:
        return super.getDefaultProperty<T>(property);
    }
  }

  List add(dynamic item) {
    if (item is ListItem) {
      childElements.add(item);
    } else if (item is String) {
      childElements.add(ListItem(item));
    } else if (item != null) {
      // iText allows adding other things to List?
      // List.cs Add(ListItem) is the main one.
      // Add(String) creates a ListItem.
      childElements.add(item);
    }
    return this;
  }

  List setItemStartIndex(int start) {
    setProperty(Property.LIST_START, start);
    return this;
  }

  List setListSymbol(dynamic symbol) {
    if (symbol is String) {
      setProperty(Property.LIST_SYMBOL, Text(symbol));
    } else if (symbol is Text ||
        symbol is ListNumberingType ||
        symbol is Image) {
      if (symbol is ListNumberingType) {
        if (symbol == ListNumberingType.ZAPF_DINGBATS_1 ||
            symbol == ListNumberingType.ZAPF_DINGBATS_2 ||
            symbol == ListNumberingType.ZAPF_DINGBATS_3 ||
            symbol == ListNumberingType.ZAPF_DINGBATS_4) {
          setPostSymbolText(" ");
        }
      }
      setProperty(Property.LIST_SYMBOL, symbol);
    }
    return this;
  }

  List setListSymbolAlignment(ListSymbolAlignment alignment) {
    setProperty(Property.LIST_SYMBOL_ALIGNMENT, alignment);
    return this;
  }

  double? getSymbolIndent() {
    return getProperty<double?>(Property.LIST_SYMBOL_INDENT);
  }

  List setSymbolIndent(double symbolIndent) {
    setProperty(Property.LIST_SYMBOL_INDENT, symbolIndent);
    return this;
  }

  String? getPostSymbolText() {
    return getProperty<String?>(Property.LIST_SYMBOL_POST_TEXT);
  }

  void setPostSymbolText(String postSymbolText) {
    setProperty(Property.LIST_SYMBOL_POST_TEXT, postSymbolText);
  }

  String? getPreSymbolText() {
    return getProperty<String?>(Property.LIST_SYMBOL_PRE_TEXT);
  }

  void setPreSymbolText(String preSymbolText) {
    setProperty(Property.LIST_SYMBOL_PRE_TEXT, preSymbolText);
  }

  @override
  IRenderer makeNewRenderer() {
    return ListRenderer(this);
  }
}
