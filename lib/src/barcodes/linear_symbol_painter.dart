import 'barcode_1d.dart';
import '../kernel/colors/color.dart';
import '../kernel/geom/rectangle.dart';
import '../kernel/pdf/canvas/pdf_canvas.dart';

/// Draws alternating runs and aligns the optional label within their union.
Future<void> drawLinearSymbol(
    CraftBarcode1D symbol,
    CraftPdfCanvas canvas,
    List<double> runs,
    String label,
    CraftColor? barColor,
    CraftColor? textColor) async {
  final barWidth = runs.fold<double>(0, (sum, width) => sum + width);
  final labelWidth = symbol.font?.getWidthPoint(label, symbol.size) ?? 0.0;
  final width = barWidth > labelWidth ? barWidth : labelWidth;
  final alignment = switch (symbol.textAlignment) {
    CraftBarcode1D.ALIGN_LEFT => 0.0,
    CraftBarcode1D.ALIGN_RIGHT => 1.0,
    _ => 0.5,
  };
  final textY = symbol.font == null
      ? 0.0
      : symbol.baseline > 0
          ? -symbol.getDescender()
          : symbol.barHeight - symbol.baseline;
  final bottom = symbol.font != null && symbol.baseline > 0
      ? textY + symbol.baseline
      : 0.0;
  var left = (width - barWidth) * alignment;
  if (barColor != null) canvas.setFillColor(barColor);
  for (var index = 0; index < runs.length; index += 2) {
    canvas.rectangle(
        left, bottom, runs[index] - symbol.inkSpreading, symbol.barHeight);
    left += runs[index];
    if (index + 1 < runs.length) left += runs[index + 1];
  }
  canvas.fill();
  final typeface = symbol.font;
  if (typeface == null) return;
  if (textColor != null) canvas.setFillColor(textColor);
  canvas.beginText();
  await canvas.setFontAndSize(typeface, symbol.size);
  canvas.setTextMatrixSimple((width - labelWidth) * alignment, textY);
  canvas.showText(label);
  canvas.endText();
}

/// Bounds of the bars and optional label, including their baseline gap.
CraftRectangle measureLinearSymbol(
    CraftBarcode1D symbol, List<double> runs, String label) {
  final bars = runs.fold<double>(0, (sum, width) => sum + width);
  final text = symbol.font?.getWidthPoint(label, symbol.size) ?? 0.0;
  final labelHeight = symbol.font == null
      ? 0.0
      : symbol.baseline > 0
          ? symbol.baseline - symbol.getDescender()
          : symbol.size - symbol.baseline;
  return CraftRectangle(
      0, 0, bars > text ? bars : text, symbol.barHeight + labelHeight);
}
