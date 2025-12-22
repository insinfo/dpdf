import 'package:dpdf/src/layout/element/i_element.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';

import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';

import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/background.dart';
import 'package:dpdf/src/layout/borders/border.dart';
import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

abstract class AbstractRenderer implements IRenderer {
  IElement? modelElement;
  List<IRenderer> childRenderers = [];
  IRenderer? parent;
  Map<int, dynamic> properties = {};
  LayoutArea? occupiedArea;

  AbstractRenderer(this.modelElement);

  @override
  IElement? getModelElement() {
    return modelElement;
  }

  @override
  Future<void> addChild(IRenderer renderer) async {
    childRenderers.add(renderer);
    renderer.setParent(this);
  }

  @override
  void setParent(IRenderer parent) {
    this.parent = parent;
  }

  @override
  IRenderer? getNextRenderer() {
    return null;
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

  // Property helpers
  T? getProperty<T>(int property) {
    if (properties.containsKey(property)) {
      return properties[property] as T?;
    }
    // Check model
    if (modelElement != null && modelElement!.hasProperty(property)) {
      return modelElement!.getProperty(property);
    }
    // Check parent (if applicable, though usually properties are inherited explicitly in iText logic, but simplified here)
    // For now, assume modelElement has it.
    return null;
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
}
