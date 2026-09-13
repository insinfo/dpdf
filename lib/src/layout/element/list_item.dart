import 'package:dpdf/src/layout/element/div.dart';
import 'package:dpdf/src/layout/element/image.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/list_numbering_type.dart';
import 'package:dpdf/src/layout/properties/list_symbol_position.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/renderer/list_item_renderer.dart';
import 'package:dpdf/src/kernel/pdf/tagging/standard_roles.dart';
import 'package:dpdf/src/layout/tagging/default_accessibility_properties.dart';

class ListItem extends Div {
  DefaultAccessibilityProperties? _listItemAccessibilityProperties;

  ListItem([dynamic content]) : super() {
    if (content is String) {
      add(Paragraph(content).setMarginTop(0).setMarginBottom(0));
    } else if (content != null) {
      add(content);
    }
  }

  ListItem setListSymbolOrdinalValue(int ordinalValue) {
    setProperty(Property.LIST_SYMBOL_ORDINAL_VALUE, ordinalValue);
    return this;
  }

  @override
  T? getDefaultProperty<T>(int property) {
    switch (property) {
      case Property.LIST_SYMBOL_POSITION:
        return ListSymbolPosition.DEFAULT as T;
      default:
        return super.getDefaultProperty<T>(property);
    }
  }

  /// Sets the symbol drawn in front of this item. Accepted values are a
  /// [String], a [Text], an [Image] used as a bullet, or a [ListNumberingType].
  ListItem setListSymbol(dynamic symbol) {
    if (symbol is String) {
      setProperty(Property.LIST_SYMBOL, Text(symbol));
    } else if (symbol is Text ||
        symbol is Image ||
        symbol is ListNumberingType) {
      if (symbol is ListNumberingType) {
        if (symbol == ListNumberingType.ZAPF_DINGBATS_1 ||
            symbol == ListNumberingType.ZAPF_DINGBATS_2 ||
            symbol == ListNumberingType.ZAPF_DINGBATS_3 ||
            symbol == ListNumberingType.ZAPF_DINGBATS_4) {
          setProperty(Property.LIST_SYMBOL_POST_TEXT, " ");
        }
      }
      setProperty(Property.LIST_SYMBOL, symbol);
    } else if (symbol != null) {
      throw ArgumentError(
          'List symbol must be a String, Text, Image or ListNumberingType.');
    }
    return this;
  }

  @override
  DefaultAccessibilityProperties getAccessibilityProperties() {
    return _listItemAccessibilityProperties ??=
        DefaultAccessibilityProperties(StandardRoles.li);
  }

  @override
  Renderer makeNewRenderer() {
    return ListItemRenderer(this);
  }
}
