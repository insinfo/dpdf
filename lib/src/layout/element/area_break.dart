import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/layout/element/abstract_element.dart';
import 'package:dpdf/src/layout/element/block_content.dart';
import 'package:dpdf/src/layout/properties/area_break_type.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/renderer/area_break_renderer.dart';

/// Forces the content that follows it to be placed on a new area.
class AreaBreak extends AbstractElement implements BlockContent {
  PageSize? pageSize;

  AreaBreak([AreaBreakType type = AreaBreakType.NEXT_AREA]) {
    setProperty(Property.AREA_BREAK_TYPE, type);
  }

  /// Creates a break that starts a new page with the given size.
  AreaBreak.withPageSize(PageSize pageSize) {
    this.pageSize = pageSize;
    setProperty(Property.AREA_BREAK_TYPE, AreaBreakType.NEXT_PAGE);
  }

  AreaBreakType getAreaBreakType() =>
      getProperty<AreaBreakType>(Property.AREA_BREAK_TYPE) ??
      AreaBreakType.NEXT_AREA;

  void setAreaBreakType(AreaBreakType type) {
    setProperty(Property.AREA_BREAK_TYPE, type);
  }

  PageSize? getPageSize() => pageSize;

  void setPageSize(PageSize? pageSize) {
    this.pageSize = pageSize;
  }

  @override
  Renderer makeNewRenderer() {
    return AreaBreakRenderer(this);
  }
}
