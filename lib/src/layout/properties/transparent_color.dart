import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/extgstate/pdf_ext_g_state.dart';

/// Represents a color with the specified opacity.
class CraftTransparentColor {
  final CraftColor color;
  final double opacity;

  /// Creates a new TransparentColor instance of certain fully opaque color.
  CraftTransparentColor(this.color, [this.opacity = 1.0]);

  /// Gets the color.
  CraftColor getColor() => color;

  /// Gets the opacity of color.
  double getOpacity() => opacity;

  /// Sets the opacity value for non-stroking operations in the transparent imaging model.
  void applyFillTransparency(CraftPdfCanvas canvas) {
    _applyTransparency(canvas, false);
  }

  /// Sets the opacity value for stroking operations in the transparent imaging model.
  void applyStrokeTransparency(CraftPdfCanvas canvas) {
    _applyTransparency(canvas, true);
  }

  void _applyTransparency(CraftPdfCanvas canvas, bool isStroke) {
    if (isTransparent()) {
      CraftPdfExtGState extGState = CraftPdfExtGState();
      if (isStroke) {
        extGState.setStrokeOpacity(opacity);
      } else {
        extGState.setFillOpacity(opacity);
      }
      canvas.setExtGState(extGState);
    }
  }

  bool isTransparent() => opacity < 1.0;
}
