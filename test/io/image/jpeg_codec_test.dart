import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dpdf/src/io/image/jpeg_decoder.dart';
import 'package:dpdf/src/io/image/jpeg_encoder.dart';
import 'package:test/test.dart';

/// Peak signal-to-noise ratio in decibels. Infinity when the two are equal.
double _psnr(Uint8List a, Uint8List b) {
  expect(a.length, equals(b.length));
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    final delta = a[i] - b[i];
    sum += delta * delta;
  }
  final mse = sum / a.length;
  return mse == 0 ? double.infinity : 10 * (log(255 * 255 / mse) / ln10);
}

Uint8List _solid(int width, int height, List<int> colour) {
  final pixels = Uint8List(width * height * 3);
  for (var i = 0; i < pixels.length; i += 3) {
    pixels[i] = colour[0];
    pixels[i + 1] = colour[1];
    pixels[i + 2] = colour[2];
  }
  return pixels;
}

/// A smooth gradient with a little structure, which exercises the AC
/// coefficients without being noise.
Uint8List _gradient(int width, int height) {
  final pixels = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      pixels[i] = (x * 255 ~/ (width - 1));
      pixels[i + 1] = (y * 255 ~/ (height - 1));
      pixels[i + 2] = ((x + y) * 255 ~/ (width + height - 2));
    }
  }
  return pixels;
}

void main() {
  group('JpegDecoder on files written by other encoders', () {
    late Uint8List desert;

    setUpAll(() {
      desert = File('test/assets/Desert.jpg').readAsBytesSync();
    });

    test('probes the frame header without decoding', () {
      final info = JpegDecoder.probe(desert);

      expect(info.width, equals(160));
      expect(info.height, equals(100));
      expect(info.components, equals(3));
      expect(info.decodable, isTrue);
      expect(info.pixelCount, equals(16000));
    });

    test('decodes a photograph to the declared number of samples', () {
      final image = JpegDecoder.decode(desert);

      expect(image.width, equals(160));
      expect(image.height, equals(100));
      expect(image.format, equals(JpegPixelFormat.rgb));
      expect(image.bytesPerPixel, equals(3));
      expect(image.pixels, hasLength(160 * 100 * 3));
    });

    test('produces a picture rather than a flat or clipped field', () {
      final pixels = JpegDecoder.decode(desert).pixels;

      var min = 255, max = 0;
      var sum = 0;
      for (final value in pixels) {
        if (value < min) min = value;
        if (value > max) max = value;
        sum += value;
      }
      // A decoder that mis-orders coefficients or drops the level shift gives
      // a flat grey or a saturated field; a real photograph does neither.
      expect(max - min, greaterThan(200), reason: 'range $min..$max');
      final mean = sum / pixels.length;
      expect(mean, greaterThan(20));
      expect(mean, lessThan(235));
    });

    test('rejects what it cannot decode instead of guessing', () {
      expect(() => JpegDecoder.decode(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<JpegDecodeException>()));
      expect(() => JpegDecoder.decode(Uint8List(0)),
          throwsA(isA<JpegDecodeException>()));
    });
  });

  group('JpegEncoder', () {
    test('reproduces a solid colour exactly, which is the DC-only case', () {
      const width = 64, height = 48;
      final source = _solid(width, height, [200, 100, 50]);

      final decoded = JpegDecoder.decode(JpegEncoder.encode(
        source,
        width: width,
        height: height,
        quality: 100,
        subsampling: JpegSubsampling.none,
      ));

      expect(decoded.width, equals(width));
      expect(decoded.height, equals(height));
      expect(decoded.pixels[0], equals(200));
      expect(decoded.pixels[1], equals(100));
      expect(decoded.pixels[2], equals(50));
      // Every pixel, not just the first.
      expect(_psnr(source, decoded.pixels), greaterThan(45));
    });

    test('round-trips a gradient at high quality', () {
      const width = 96, height = 64;
      final source = _gradient(width, height);

      final decoded = JpegDecoder.decode(JpegEncoder.encode(
        source,
        width: width,
        height: height,
        quality: 95,
        subsampling: JpegSubsampling.none,
      ));

      expect(_psnr(source, decoded.pixels), greaterThan(38));
    });

    test('round-trips grayscale, including a non-MCU-multiple size', () {
      const width = 37, height = 23;
      final source = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          source[y * width + x] = (x * 7 + y * 3) & 0xff;
        }
      }

      final decoded = JpegDecoder.decode(JpegEncoder.encode(
        source,
        width: width,
        height: height,
        format: JpegPixelFormat.grayscale,
        quality: 95,
      ));

      expect(decoded.width, equals(width));
      expect(decoded.height, equals(height));
      expect(decoded.format, equals(JpegPixelFormat.grayscale));
      expect(_psnr(source, decoded.pixels), greaterThan(35));
    });

    test('higher quality costs more bytes and loses less', () {
      const width = 96, height = 64;
      final source = _gradient(width, height);

      var previousSize = 0;
      var previousPsnr = 0.0;
      for (final quality in [30, 60, 90]) {
        final encoded = JpegEncoder.encode(source,
            width: width,
            height: height,
            quality: quality,
            subsampling: JpegSubsampling.none);
        final psnr = _psnr(source, JpegDecoder.decode(encoded).pixels);

        expect(encoded.length, greaterThan(previousSize),
            reason: 'quality $quality');
        expect(psnr, greaterThan(previousPsnr), reason: 'quality $quality');
        previousSize = encoded.length;
        previousPsnr = psnr;
      }
    });

    test('chroma subsampling makes the file smaller', () {
      final source = _gradient(96, 64);

      final full = JpegEncoder.encode(source,
          width: 96, height: 64, subsampling: JpegSubsampling.none);
      final half = JpegEncoder.encode(source,
          width: 96, height: 64, subsampling: JpegSubsampling.chroma420);

      expect(half.length, lessThan(full.length));
    });

    test('writes a file its own probe recognises', () {
      final encoded = JpegEncoder.encode(_gradient(40, 24),
          width: 40, height: 24, quality: 80);

      final info = JpegDecoder.probe(encoded);
      expect(info.width, equals(40));
      expect(info.height, equals(24));
      expect(info.components, equals(3));
      expect(info.decodable, isTrue);
      // SOI and EOI, so the file is complete.
      expect(encoded.first, equals(0xFF));
      expect(encoded[1], equals(0xD8));
      expect(encoded[encoded.length - 2], equals(0xFF));
      expect(encoded.last, equals(0xD9));
    });

    test(
        're-encoding a real photograph is near lossless above its own '
        'quality', () {
      final original =
          JpegDecoder.decode(File('test/assets/Desert.jpg').readAsBytesSync());

      final again = JpegDecoder.decode(JpegEncoder.encode(
        original.pixels,
        width: original.width,
        height: original.height,
        quality: 95,
        subsampling: JpegSubsampling.none,
      ));

      // The source was itself quantised, so encoding it again at a higher
      // quality preserves the coefficients it already had.
      expect(_psnr(original.pixels, again.pixels), greaterThan(45));
    });

    test('rejects arguments it cannot honour', () {
      final pixels = _solid(8, 8, [0, 0, 0]);

      expect(() => JpegEncoder.encode(pixels, width: 0, height: 8),
          throwsArgumentError);
      expect(() => JpegEncoder.encode(pixels, width: 8, height: 8, quality: 0),
          throwsArgumentError);
      expect(
          () => JpegEncoder.encode(pixels, width: 8, height: 8, quality: 101),
          throwsArgumentError);
      expect(() => JpegEncoder.encode(Uint8List(4), width: 8, height: 8),
          throwsArgumentError);
      expect(
          () => JpegEncoder.encode(pixels,
              width: 8, height: 8, format: JpegPixelFormat.cmyk),
          throwsArgumentError);
    });
  });
}
