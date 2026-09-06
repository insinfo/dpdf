import 'dart:io';
import 'package:test/test.dart';
import 'package:dpdf/src/io/image/image_data_factory.dart';
import 'package:dpdf/src/io/image/bmp_image_data.dart';
import 'package:dpdf/src/io/image/jbig2_image_data.dart';
import 'package:dpdf/src/io/image/raw_image_data.dart';

void main() {
  group('Image Helper Tests', () {
    test('BMP Image Helper Test', () async {
      final file = File('test/assets/WP_20140410_001.bmp');
      final bytes = await file.readAsBytes();
      final imageData = ImageDataFactory.create(bytes);

      expect(imageData, isA<BmpImageData>());
      expect(imageData.getWidth(), 2592.0);
      expect(imageData.getHeight(), 1456.0);
    });

    test('GIF Image Helper Test', () async {
      final file = File('test/assets/bulb.gif');
      final bytes = await file.readAsBytes();
      final imageData = ImageDataFactory.create(bytes);

      expect(imageData, isA<RawImageData>());
      expect(imageData.getWidth(), 16.0);
      expect(imageData.getHeight(), 16.0);
    });

    test('GIF Multi-frame Test', () async {
      final file = File('test/assets/image-2frames.gif');
      final bytes = await file.readAsBytes();
      final imageData = ImageDataFactory.create(bytes);
      expect(imageData, isA<RawImageData>());
      expect(imageData.getWidth(), 50.0);
      expect(imageData.getHeight(), 50.0);
    });

    test('JBIG2 Image Helper Test', () async {
      final file = File('test/assets/image.jb2');
      final bytes = await file.readAsBytes();
      final imageData = ImageDataFactory.create(bytes);

      expect(imageData, isA<Jbig2ImageData>());
      expect(imageData.getWidth(), 100.0);
      expect(imageData.getHeight(), 100.0);
    });
  });
}
