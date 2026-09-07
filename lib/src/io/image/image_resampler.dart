import 'dart:typed_data';

/// Scales interleaved 8-bit images.
///
/// Downscaling uses a box filter: every output pixel is the average of the
/// input pixels it covers. That is the right filter for making an image
/// smaller — it uses all the source pixels, so it neither aliases the way
/// point sampling does nor invents detail. Upscaling is refused, because a
/// compressor that enlarges an image has misunderstood its job.
abstract final class ImageResampler {
  /// Scales [pixels] to [targetWidth] by [targetHeight].
  ///
  /// [channels] is the number of interleaved samples per pixel, so 1 for
  /// grayscale, 3 for RGB and 4 for CMYK or RGBA.
  static Uint8List resize(
    Uint8List pixels, {
    required int width,
    required int height,
    required int targetWidth,
    required int targetHeight,
    required int channels,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('The source must have a positive extent.');
    }
    if (targetWidth <= 0 || targetHeight <= 0) {
      throw ArgumentError('The target must have a positive extent.');
    }
    if (channels < 1 || channels > 4) {
      throw ArgumentError.value(channels, 'channels', 'must be from 1 to 4');
    }
    final needed = width * height * channels;
    if (pixels.length < needed) {
      throw ArgumentError('pixels holds ${pixels.length} bytes, but $needed '
          'are needed for a ${width}x$height image of $channels channels.');
    }
    if (targetWidth > width || targetHeight > height) {
      throw ArgumentError('Upscaling is not supported: '
          '${width}x$height to ${targetWidth}x$targetHeight.');
    }
    if (targetWidth == width && targetHeight == height) {
      return pixels;
    }

    final out = Uint8List(targetWidth * targetHeight * channels);
    final accumulator = Float64List(channels);

    for (var ty = 0; ty < targetHeight; ty++) {
      // The source band this output row covers, in whole pixels.
      final y0 = ty * height ~/ targetHeight;
      var y1 = (ty + 1) * height ~/ targetHeight;
      if (y1 <= y0) y1 = y0 + 1;

      for (var tx = 0; tx < targetWidth; tx++) {
        final x0 = tx * width ~/ targetWidth;
        var x1 = (tx + 1) * width ~/ targetWidth;
        if (x1 <= x0) x1 = x0 + 1;

        accumulator.fillRange(0, channels, 0);
        var count = 0;
        for (var sy = y0; sy < y1 && sy < height; sy++) {
          var index = (sy * width + x0) * channels;
          for (var sx = x0; sx < x1 && sx < width; sx++) {
            for (var c = 0; c < channels; c++) {
              accumulator[c] += pixels[index + c];
            }
            index += channels;
            count++;
          }
        }
        if (count == 0) count = 1;

        final at = (ty * targetWidth + tx) * channels;
        for (var c = 0; c < channels; c++) {
          out[at + c] = (accumulator[c] / count).round().clamp(0, 255);
        }
      }
    }
    return out;
  }

  /// The largest size that fits inside [maxDimension] on both axes while
  /// keeping the aspect ratio, or null when the image already fits.
  ///
  /// Never returns a dimension below 1, so a very wide, very short image does
  /// not collapse to nothing.
  static ({int width, int height})? fit({
    required int width,
    required int height,
    required int maxDimension,
  }) {
    if (maxDimension <= 0) {
      throw ArgumentError.value(
          maxDimension, 'maxDimension', 'must be positive');
    }
    if (width <= maxDimension && height <= maxDimension) return null;

    final scale = maxDimension / (width > height ? width : height);
    final targetWidth = (width * scale).round().clamp(1, width);
    final targetHeight = (height * scale).round().clamp(1, height);
    if (targetWidth == width && targetHeight == height) return null;
    return (width: targetWidth, height: targetHeight);
  }
}
