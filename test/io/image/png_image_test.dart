import 'dart:io';
import 'package:test/test.dart';
import 'package:dpdf/src/io/image/png_image_helper.dart';
import 'package:dpdf/src/io/image/png_image_data.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';

void main() {
  group('PngImageHelper Tests', () {
    test('Process bee.png', () async {
      final file = File('test/assets/bee.png');
      expect(await file.exists(), isTrue);

      final bytes = await file.readAsBytes();
      final image = PngImageData.fromBytes(bytes);

      // Initially, PngImageData might not have all info until processed
      PngImageHelper.processImage(image);

      print('Bee PNG Width: ${image.width}');
      print('Bee PNG Height: ${image.height}');
      print('Bee PNG BPC: ${image.bpc}');
      print('Bee PNG Components: ${image.colorEncodingComponentsNumber}');

      expect(image.width, greaterThan(0));
      expect(image.height, greaterThan(0));
      expect(image.getOriginalType(), ImageType.PNG);
      expect(image.getData(), isNotNull);
    });

    test('Process png_greyscale.png', () async {
      final file = File('test/assets/png_greyscale.png');
      expect(await file.exists(), isTrue);

      final bytes = await file.readAsBytes();
      final image = PngImageData.fromBytes(bytes);

      PngImageHelper.processImage(image);

      print('Greyscale PNG Width: ${image.width}');
      print('Greyscale PNG Height: ${image.height}');
      print('Greyscale PNG BPC: ${image.bpc}');
      print('Greyscale PNG Components: ${image.colorEncodingComponentsNumber}');

      expect(image.width, greaterThan(0));
      expect(image.height, greaterThan(0));
      expect(image.colorEncodingComponentsNumber, 1);
    });
  });
}
