import 'package:pdfcraft/src/layout/property_container.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';

import 'package:pdfcraft/src/layout/layout/layout_context.dart';
import 'package:pdfcraft/src/layout/layout/layout_result.dart';
import 'package:pdfcraft/src/layout/renderer/draw_context.dart';
import 'package:pdfcraft/src/layout/layout/layout_area.dart';

import 'package:pdfcraft/src/layout/properties/unit_value.dart';
import 'package:pdfcraft/src/layout/properties/property.dart';
import 'package:pdfcraft/src/layout/properties/background.dart';
import 'package:pdfcraft/src/layout/borders/border.dart';
import 'package:pdfcraft/src/kernel/geom/rectangle.dart';
import 'package:pdfcraft/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:pdfcraft/src/layout/minmaxwidth/min_max_width.dart';

abstract class CraftAbstractRenderer implements CraftRenderer {
  CraftPropertyContainer? modelElement;
  List<CraftRenderer> childRenderers = [];
  CraftRenderer? parent;
  Map<int, dynamic> properties = {};
  CraftLayoutArea? occupiedArea;

  CraftAbstractRenderer(this.modelElement);

  @override
  @override
  CraftPropertyContainer? getModelElement() {
    return modelElement;
  }

  @override
  void addChild(CraftRenderer renderer) {
    childRenderers.add(renderer);
    renderer.setParent(this);
  }

  @override
  List<CraftRenderer> getChildRenderers() {
    return childRenderers;
  }

  @override
  void setParent(CraftRenderer? parent) {
    this.parent = parent;
  }

  @override
  CraftLayoutArea? getOccupiedArea() {
    return occupiedArea;
  }

  @override
  CraftRenderer? getNextRenderer() {
    return null;
  }

  CraftAbstractRenderer createSplitRenderer(int layoutResult) {
    CraftAbstractRenderer splitRenderer =
        getNextRenderer() as CraftAbstractRenderer;
    splitRenderer.modelElement = modelElement;
    splitRenderer.parent = parent;
    splitRenderer.occupiedArea = occupiedArea;
    return splitRenderer;
  }

  CraftAbstractRenderer createOverflowRenderer(int layoutResult) {
    CraftAbstractRenderer overflowRenderer =
        getNextRenderer() as CraftAbstractRenderer;
    overflowRenderer.modelElement = modelElement;
    overflowRenderer.parent = parent;
    return overflowRenderer;
  }

  @override
  Future<void> draw(CraftDrawContext drawContext) async {
    drawBackground(drawContext);
    drawBorder(drawContext);
    await drawChildren(drawContext);
  }

  void drawBackground(CraftDrawContext drawContext) {
    CraftBackground? background = getProperty(CraftProperty.BACKGROUND);
    if (background != null &&
        background.color != null &&
        occupiedArea != null) {
      CraftRectangle box = applyMargins(occupiedArea!.getBBox(), false);

      CraftPdfCanvas canvas = drawContext.getCanvas();
      canvas.saveState();
      canvas.setFillColor(background.color!);
      canvas.rectangle(box.getX(), box.getY(), box.getWidth(), box.getHeight());
      canvas.fill();
      canvas.restoreState();
    }
  }

  void drawBorder(CraftDrawContext drawContext) {
    if (occupiedArea == null) return;
    CraftRectangle box = applyMargins(occupiedArea!.getBBox(), true);

    CraftBorder? bt = getProperty(CraftProperty.BORDER_TOP);
    CraftBorder? bb = getProperty(CraftProperty.BORDER_BOTTOM);
    CraftBorder? bl = getProperty(CraftProperty.BORDER_LEFT);
    CraftBorder? br = getProperty(CraftProperty.BORDER_RIGHT);

    CraftPdfCanvas canvas = drawContext.getCanvas();
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

  CraftRectangle applyMargins(CraftRectangle rect, bool applyBorders) {
    double parentWidth = rect.getWidth();

    double mt = getResolvedProperty(CraftProperty.MARGIN_TOP, parentWidth);
    double mb = getResolvedProperty(CraftProperty.MARGIN_BOTTOM, parentWidth);
    double ml = getResolvedProperty(CraftProperty.MARGIN_LEFT, parentWidth);
    double mr = getResolvedProperty(CraftProperty.MARGIN_RIGHT, parentWidth);

    return CraftRectangle(rect.getX() + ml, rect.getY() + mb,
        rect.getWidth() - ml - mr, rect.getHeight() - mt - mb);
  }

  Future<void> drawChildren(CraftDrawContext drawContext) async {
    for (var child in childRenderers) {
      await child.draw(drawContext);
    }
  }

  // Define layout as abstract (no body needed in abstract class)
  @override
  CraftLayoutResult? layout(CraftLayoutContext layoutContext);

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
    // Inherit from parent
    if (parent != null) {
      return parent!.getProperty<T>(property);
    }
    return null;
  }

  @override
  T? getOwnProperty<T>(int property) {
    return properties[property] as T?;
  }

  @override
  T? getDefaultProperty<T>(int property) {
    return null; // TODO: Implement defaults
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
    if (val is CraftUnitValue && val.isPointValue()) return val.getValue();
    return null;
  }

  // Basic helper for unit values which might be points or percents
  double getResolvedProperty(int property, double parentWidth,
      [double defaultValue = 0]) {
    var val = getProperty(property);
    if (val is num) return val.toDouble();
    if (val is CraftUnitValue) {
      if (val.isPointValue()) return val.getValue();
      if (val.isPercentValue()) return val.getValue() * parentWidth / 100.0;
    }
    return defaultValue;
  }

  @override
  CraftMinMaxWidth? getMinMaxWidth() {
    return CraftMinMaxWidth(0);
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
      if (child is CraftAbstractRenderer) {
        double? y = child.getFirstYLineRecursively();
        if (y != null) return y;
      }
    }
    return null;
  }
}
