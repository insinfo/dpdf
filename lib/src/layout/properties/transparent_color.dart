import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/extgstate/pdf_ext_g_state.dart';

/// Represents a color with the specified opacity.
class TransparentColor {
  final Color color;
  final double opacity;

  /// Creates a new TransparentColor instance of certain fully opaque color.
  TransparentColor(this.color, [this.opacity = 1.0]);

  /// Gets the color.
  Color getColor() => color;

  /// Gets the opacity of color.
  double getOpacity() => opacity;

  /// Sets the opacity value for non-stroking operations in the transparent imaging model.
  Future<void> applyFillTransparency(PdfCanvas canvas) =>
      _applyTransparency(canvas, false);

  /// Sets the opacity value for stroking operations in the transparent imaging model.
  Future<void> applyStrokeTransparency(PdfCanvas canvas) =>
      _applyTransparency(canvas, true);

  /// The graphics state has to reach the content stream before the operators
  /// it governs, and registering it in the resource dictionary is asynchronous,
  /// so the caller has to wait for it.
  Future<void> _applyTransparency(PdfCanvas canvas, bool isStroke) async {
    if (isTransparent()) {
      PdfExtGState extGState = PdfExtGState();
      if (isStroke) {
        extGState.setStrokeOpacity(opacity);
      } else {
        extGState.setFillOpacity(opacity);
      }
      await canvas.setExtGState(extGState);
    }
  }

  bool isTransparent() => opacity < 1.0;
}
