import 'dart:typed_data';

import 'package:dpdf/src/io/image/image_resampler.dart';
import 'package:test/test.dart';

void main() {
  group('ImageResampler.resize', () {
    test('averages each source block, it does not point sample', () {
      // A 4x4 ramp halved: every output is the mean of its 2x2 group.
      final source = Uint8List.fromList([
        0, 10, 20, 30, //
        40, 50, 60, 70,
        80, 90, 100, 110,
        120, 130, 140, 150,
      ]);

      final halved = ImageResampler.resize(source,
          width: 4, height: 4, targetWidth: 2, targetHeight: 2, channels: 1);

      expect(halved, equals([25, 45, 105, 125]));
    });

    test('keeps channels separate', () {
      final source = Uint8List.fromList([
        0, 100, 200, 20, 120, 220, //
        40, 140, 240, 60, 160, 255,
      ]);

      final halved = ImageResampler.resize(source,
          width: 2, height: 2, targetWidth: 1, targetHeight: 1, channels: 3);

      expect(halved, hasLength(3));
      expect(halved[0], equals((0 + 20 + 40 + 60) ~/ 4));
      expect(halved[1], equals((100 + 120 + 140 + 160) ~/ 4));
      expect(halved[2], equals(((200 + 220 + 240 + 255) / 4).round()));
    });

    test('returns the input untouched at the same size', () {
      final source = Uint8List.fromList([1, 2, 3, 4]);

      final same = ImageResampler.resize(source,
          width: 2, height: 2, targetWidth: 2, targetHeight: 2, channels: 1);

      expect(identical(same, source), isTrue);
    });

    test('handles a non-integer scale without leaving a blank row', () {
      final source = Uint8List(7 * 5)..fillRange(0, 35, 200);

      final scaled = ImageResampler.resize(source,
          width: 7, height: 5, targetWidth: 3, targetHeight: 2, channels: 1);

      expect(scaled, hasLength(6));
      expect(scaled.every((v) => v == 200), isTrue);
    });

    test('refuses to enlarge', () {
      final source = Uint8List(4);

      expect(
        () => ImageResampler.resize(source,
            width: 2, height: 2, targetWidth: 4, targetHeight: 4, channels: 1),
        throwsArgumentError,
      );
    });

    test('rejects sizes and buffers it cannot honour', () {
      final source = Uint8List(4);

      expect(
          () => ImageResampler.resize(source,
              width: 0,
              height: 2,
              targetWidth: 1,
              targetHeight: 1,
              channels: 1),
          throwsArgumentError);
      expect(
          () => ImageResampler.resize(source,
              width: 2,
              height: 2,
              targetWidth: 0,
              targetHeight: 1,
              channels: 1),
          throwsArgumentError);
      expect(
          () => ImageResampler.resize(source,
              width: 2,
              height: 2,
              targetWidth: 1,
              targetHeight: 1,
              channels: 9),
          throwsArgumentError);
      expect(
          () => ImageResampler.resize(Uint8List(3),
              width: 2,
              height: 2,
              targetWidth: 1,
              targetHeight: 1,
              channels: 1),
          throwsArgumentError);
    });
  });

  group('ImageResampler.fit', () {
    test('scales the larger side down to the cap', () {
      expect(ImageResampler.fit(width: 4000, height: 3000, maxDimension: 1000),
          equals((width: 1000, height: 750)));
      expect(ImageResampler.fit(width: 3000, height: 4000, maxDimension: 1000),
          equals((width: 750, height: 1000)));
    });

    test('returns nothing when the image already fits', () {
      expect(ImageResampler.fit(width: 800, height: 600, maxDimension: 1000),
          isNull);
      expect(ImageResampler.fit(width: 1000, height: 1000, maxDimension: 1000),
          isNull);
    });

    test('never collapses an extreme aspect ratio to nothing', () {
      final fitted =
          ImageResampler.fit(width: 5000, height: 10, maxDimension: 1000);

      expect(fitted!.width, equals(1000));
      expect(fitted.height, greaterThanOrEqualTo(1));
    });

    test('rejects a non-positive cap', () {
      expect(() => ImageResampler.fit(width: 10, height: 10, maxDimension: 0),
          throwsArgumentError);
    });
  });
}
