import 'byte_matrix.dart';
import 'encode_hint_type.dart';
import 'encoder.dart';
import 'error_correction_level.dart';
import 'qr_code.dart';

/// Produces a centered black-on-white raster with a four-module quiet zone.
class CraftQRCodeWriter {
  CraftByteMatrix encode(String contents, int width, int height,
      [Map<CraftEncodeHintType, dynamic>? hints]) {
    if (contents.isEmpty) {
      throw ArgumentError('A QR raster needs nonempty content');
    }
    RangeError.checkNotNegative(width, 'width');
    RangeError.checkNotNegative(height, 'height');
    final level = hints?[CraftEncodeHintType.ERROR_CORRECTION]
            as CraftErrorCorrectionLevel? ??
        CraftErrorCorrectionLevel.L;
    final symbol = CraftQRCode();
    CraftEncoder.encode(contents, level, hints, symbol);
    final modules = symbol.getMatrix()!;
    final minimum = modules.getWidth() + 8;
    final outputWidth = width < minimum ? minimum : width;
    final outputHeight = height < minimum ? minimum : height;
    final horizontalScale = outputWidth ~/ minimum;
    final verticalScale = outputHeight ~/ minimum;
    final scale =
        horizontalScale < verticalScale ? horizontalScale : verticalScale;
    final left = (outputWidth - modules.getWidth() * scale) ~/ 2;
    final top = (outputHeight - modules.getHeight() * scale) ~/ 2;
    final raster = CraftByteMatrix(outputWidth, outputHeight)..clear(255);
    final rows = raster.getArray();
    for (var y = 0; y < modules.getHeight(); y++) {
      final target = top + y * scale;
      for (var x = 0; x < modules.getWidth(); x++) {
        if (modules.get(x, y) == 1) {
          rows[target].fillRange(left + x * scale, left + (x + 1) * scale, 0);
        }
      }
      for (var repeat = 1; repeat < scale; repeat++) {
        rows[target + repeat].setAll(0, rows[target]);
      }
    }
    return raster;
  }
}
