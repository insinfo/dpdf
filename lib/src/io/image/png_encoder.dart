import 'dart:typed_data';

import '../codec/png_writer.dart';

/// How the samples handed to [PngEncoder] are laid out.
enum PngPixelFormat {
  /// One byte per pixel.
  grayscale(1, 0),

  /// Two bytes per pixel: grey then alpha.
  grayscaleAlpha(2, 4),

  /// Three bytes per pixel: red, green, blue.
  rgb(3, 2),

  /// Four bytes per pixel: red, green, blue, alpha.
  rgba(4, 6);

  /// Bytes per pixel.
  final int channels;

  /// The PNG colour type this maps to.
  final int colourType;

  const PngPixelFormat(this.channels, this.colourType);
}

/// Encodes 8-bit samples as a PNG.
///
/// A thin, safe front on [CraftPngWriter]: it checks that the buffer is the
/// size the geometry implies, picks the colour type, and converts the packed
/// 32-bit forms a rasterizer produces. The writer emits one `IDAT` with the
/// `None` row filter, which deflates well enough for screen-resolution page
/// renders and keeps the encoder simple.
abstract final class PngEncoder {
  /// Encodes interleaved 8-bit [pixels], row major, top row first.
  static Uint8List encode(
    Uint8List pixels, {
    required int width,
    required int height,
    PngPixelFormat format = PngPixelFormat.rgba,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('An image must have a positive extent.');
    }
    final stride = width * format.channels;
    final needed = stride * height;
    if (pixels.length < needed) {
      throw ArgumentError('pixels holds ${pixels.length} bytes, but $needed '
          'are needed for a ${width}x$height ${format.name} image.');
    }

    final writer = CraftPngWriter()
      ..writeHeader(width, height, 8, format.colourType)
      ..writeData(
          pixels.length == needed
              ? pixels
              : Uint8List.sublistView(pixels, 0, needed),
          stride)
      ..writeEnd();
    return writer.toBytes();
  }

  /// Encodes a buffer of packed pixels, one 32-bit word each.
  ///
  /// [premultiplied] says whether the colour channels have already been
  /// multiplied by alpha; PNG stores straight alpha, so they are divided back
  /// out when they have. A word is read as `0xAARRGGBB`, which is what most
  /// rasterizers hand back.
  static Uint8List encodeArgb32(
    Uint32List pixels, {
    required int width,
    required int height,
    bool premultiplied = false,
    bool opaque = false,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('An image must have a positive extent.');
    }
    final count = width * height;
    if (pixels.length < count) {
      throw ArgumentError('pixels holds ${pixels.length} words, but $count '
          'are needed for a ${width}x$height image.');
    }

    final channels = opaque ? 3 : 4;
    final out = Uint8List(count * channels);
    for (var i = 0, at = 0; i < count; i++, at += channels) {
      final word = pixels[i];
      final a = (word >> 24) & 0xff;
      var r = (word >> 16) & 0xff;
      var g = (word >> 8) & 0xff;
      var b = word & 0xff;
      if (premultiplied && a != 0 && a != 255) {
        r = (r * 255 + a ~/ 2) ~/ a;
        g = (g * 255 + a ~/ 2) ~/ a;
        b = (b * 255 + a ~/ 2) ~/ a;
        if (r > 255) r = 255;
        if (g > 255) g = 255;
        if (b > 255) b = 255;
      }
      out[at] = r;
      out[at + 1] = g;
      out[at + 2] = b;
      if (!opaque) out[at + 3] = a;
    }

    return encode(
      out,
      width: width,
      height: height,
      format: opaque ? PngPixelFormat.rgb : PngPixelFormat.rgba,
    );
  }
}
