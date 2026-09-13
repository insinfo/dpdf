import 'package:dpdf/src/layout/property_container.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';

import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';

import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/background.dart';
import 'package:dpdf/src/layout/properties/clear_property_value.dart';
import 'package:dpdf/src/layout/properties/float_property_value.dart';
import 'package:dpdf/src/layout/properties/layout_position.dart';
import 'package:dpdf/src/layout/properties/overflow_property_value.dart';
import 'package:dpdf/src/layout/borders/border.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

abstract class AbstractRenderer implements Renderer {
  PropertyContainer? modelElement;
  List<Renderer> childRenderers = [];
  Renderer? parent;
  Map<int, dynamic> properties = {};
  LayoutArea? occupiedArea;

  AbstractRenderer(this.modelElement);

  @override
  @override
  PropertyContainer? getModelElement() {
    return modelElement;
  }

  @override
  void addChild(Renderer renderer) {
    childRenderers.add(renderer);
    renderer.setParent(this);
  }

  @override
  List<Renderer> getChildRenderers() {
    return childRenderers;
  }

  @override
  void setParent(Renderer? parent) {
    this.parent = parent;
  }

  @override
  LayoutArea? getOccupiedArea() {
    return occupiedArea;
  }

  @override
  Renderer? getNextRenderer() {
    return null;
  }

  AbstractRenderer createSplitRenderer(int layoutResult) {
    AbstractRenderer splitRenderer = getNextRenderer() as AbstractRenderer;
    splitRenderer.modelElement = modelElement;
    splitRenderer.parent = parent;
    splitRenderer.occupiedArea = occupiedArea;
    return splitRenderer;
  }

  AbstractRenderer createOverflowRenderer(int layoutResult) {
    AbstractRenderer overflowRenderer = getNextRenderer() as AbstractRenderer;
    overflowRenderer.modelElement = modelElement;
    overflowRenderer.parent = parent;
    return overflowRenderer;
  }

  @override
  Future<void> draw(DrawContext drawContext) async {
    drawBackground(drawContext);
    drawBorder(drawContext);
    await drawChildren(drawContext);
  }

  void drawBackground(DrawContext drawContext) {
    Background? background = getProperty(Property.BACKGROUND);
    if (background != null &&
        background.color != null &&
        occupiedArea != null) {
      Rectangle box = applyMargins(occupiedArea!.getBBox(), false);

      PdfCanvas canvas = drawContext.getCanvas();
      canvas.saveState();
      canvas.setFillColor(background.color!);
      canvas.rectangle(box.getX(), box.getY(), box.getWidth(), box.getHeight());
      canvas.fill();
      canvas.restoreState();
    }
  }

  void drawBorder(DrawContext drawContext) {
    if (occupiedArea == null) return;
    Rectangle box = applyMargins(occupiedArea!.getBBox(), true);

    Border? bt = getProperty(Property.BORDER_TOP);
    Border? bb = getProperty(Property.BORDER_BOTTOM);
    Border? bl = getProperty(Property.BORDER_LEFT);
    Border? br = getProperty(Property.BORDER_RIGHT);

    PdfCanvas canvas = drawContext.getCanvas();
    canvas.saveState();

    // Simplified border drawing
    if (bt != null && bt.width > 0 && bt.color != null) {
      canvas.setStrokeColor(bt.color!);
      canvas.setLineWidth(bt.width);
      canvas.moveTo(box.getX(), box.getY() + box.getHeight());
      canvas.lineTo(box.getX() + box.getWidth(), box.getY() + box.getHeight());
      canvas.stroke();
    }
    if (bb != null && bb.width > 0 && bb.color != null) {
      canvas.setStrokeColor(bb.color!);
      canvas.setLineWidth(bb.width);
      canvas.moveTo(box.getX(), box.getY());
      canvas.lineTo(box.getX() + box.getWidth(), box.getY());
      canvas.stroke();
    }
    if (bl != null && bl.width > 0 && bl.color != null) {
      canvas.setStrokeColor(bl.color!);
      canvas.setLineWidth(bl.width);
      canvas.moveTo(box.getX(), box.getY());
      canvas.lineTo(box.getX(), box.getY() + box.getHeight());
      canvas.stroke();
    }
    if (br != null && br.width > 0 && br.color != null) {
      canvas.setStrokeColor(br.color!);
      canvas.setLineWidth(br.width);
      canvas.moveTo(box.getX() + box.getWidth(), box.getY());
      canvas.lineTo(box.getX() + box.getWidth(), box.getY() + box.getHeight());
      canvas.stroke();
    }

    canvas.restoreState();
  }

  Rectangle applyMargins(Rectangle rect, bool applyBorders) {
    double parentWidth = rect.getWidth();

    double mt = getResolvedProperty(Property.MARGIN_TOP, parentWidth);
    double mb = getResolvedProperty(Property.MARGIN_BOTTOM, parentWidth);
    double ml = getResolvedProperty(Property.MARGIN_LEFT, parentWidth);
    double mr = getResolvedProperty(Property.MARGIN_RIGHT, parentWidth);

    return Rectangle(rect.getX() + ml, rect.getY() + mb,
        rect.getWidth() - ml - mr, rect.getHeight() - mt - mb);
  }

  Future<void> drawChildren(DrawContext drawContext) async {
    for (var child in childRenderers) {
      await child.draw(drawContext);
    }
  }

  // Define layout as abstract (no body needed in abstract class)
  @override
  LayoutResult? layout(LayoutContext layoutContext);

  // Property methods
  @override
  bool hasProperty(int property) {
    return getProperty(property) != null;
  }

  @override
  bool hasOwnProperty(int property) {
    return properties.containsKey(property);
  }

  @override
  T? getProperty<T>(int property) {
    if (properties.containsKey(property)) {
      return properties[property] as T?;
    }
    // Check model
    if (modelElement != null && modelElement!.hasProperty(property)) {
      return modelElement!.getProperty<T>(property);
    }
    // Inherit from parent, but only for properties which are inheritable.
    if (parent != null && Property.isPropertyInherited(property)) {
      final inherited = parent!.getProperty<T>(property);
      if (inherited != null) return inherited;
    }
    return getDefaultProperty<T>(property);
  }

  @override
  T? getOwnProperty<T>(int property) {
    return properties[property] as T?;
  }

  /// Renderer level defaults. The model element is consulted first so that a
  /// concrete element (list, list item, ...) can override them, then the
  /// generic box model defaults are applied.
  @override
  T? getDefaultProperty<T>(int property) {
    final fromModel = modelElement?.getDefaultProperty<T>(property);
    if (fromModel != null) return fromModel;
    switch (property) {
      case Property.MARGIN_TOP:
      case Property.MARGIN_BOTTOM:
      case Property.MARGIN_LEFT:
      case Property.MARGIN_RIGHT:
      case Property.PADDING_TOP:
      case Property.PADDING_BOTTOM:
      case Property.PADDING_LEFT:
      case Property.PADDING_RIGHT:
        return UnitValue.createPointValue(0) as T;
      case Property.POSITION:
        return LayoutPosition.STATIC as T;
      case Property.FLOAT:
        return FloatPropertyValue.none as T;
      case Property.CLEAR:
        return ClearPropertyValue.none as T;
      case Property.OVERFLOW_X:
      case Property.OVERFLOW_Y:
        return OverflowPropertyValue.fit as T;
      case Property.HORIZONTAL_ALIGNMENT:
        return null;
      case Property.KEEP_TOGETHER:
      case Property.KEEP_WITH_NEXT:
      case Property.FORCED_PLACEMENT:
        return false as T;
      case Property.OPACITY:
        return 1.0 as T;
      case Property.ROTATION_ANGLE:
        return 0.0 as T;
      case Property.COLSPAN:
      case Property.ROWSPAN:
        return 1 as T;
      default:
        return null;
    }
  }

  /// Out of flow boxes (floats and absolutely/fixed positioned boxes) do not
  /// take part in the vertical flow of their parent.
  bool isOutOfFlow() {
    final float = getProperty<FloatPropertyValue>(Property.FLOAT);
    if (float != null && float != FloatPropertyValue.none) return true;
    final position = getProperty<LayoutPosition>(Property.POSITION);
    return position == LayoutPosition.ABSOLUTE ||
        position == LayoutPosition.FIXED;
  }

  @override
  void setProperty(int property, Object? value) {
    properties[property] = value;
  }

  @override
  void deleteOwnProperty(int property) {
    properties.remove(property);
  }

  void addAllProperties(Map<int, dynamic> additionalProperties) {
    properties.addAll(additionalProperties);
  }

  Map<int, dynamic> getOwnProperties() {
    return properties;
  }

  bool getPropertyAsBoolean(int property) {
    var val = getProperty(property);
    if (val is bool) return val;
    return false;
  }

  double? getPropertyAsFloat(int property) {
    var val = getProperty(property);
    if (val is num) return val.toDouble();
    if (val is UnitValue && val.isPointValue()) return val.getValue();
    return null;
  }

  // Basic helper for unit values which might be points or percents
  double getResolvedProperty(int property, double parentWidth,
      [double defaultValue = 0]) {
    var val = getProperty(property);
    if (val is num) return val.toDouble();
    if (val is UnitValue) {
      if (val.isPointValue()) return val.getValue();
      if (val.isPercentValue()) return val.getValue() * parentWidth / 100.0;
    }
    return defaultValue;
  }

  @override
  MinMaxWidth? getMinMaxWidth() {
    return MinMaxWidth(0);
  }

  @override
  void move(double dx, double dy) {
    if (occupiedArea != null) {
      occupiedArea!.getBBox().move(dx, dy);
    }
  }

  double? getFirstYLineRecursively() {
    // Basic implementation for block-like renderers
    for (var child in childRenderers) {
      if (child is AbstractRenderer) {
        double? y = child.getFirstYLineRecursively();
        if (y != null) return y;
      }
    }
    return null;
  }
}
