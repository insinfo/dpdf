import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pdfcraft/src/io/image/raw_image_data.dart';
import 'package:pdfcraft/src/io/image/bmp_image_data.dart';
import 'package:pdfcraft/src/io/image/tiff_image_data.dart';
import 'package:pdfcraft/src/layout/properties/image_type.dart';

void main() {
  group('RawImageData', () {
    test('creates from bytes with CCITT constants', () {
      final data = Uint8List.fromList([0, 1, 2, 3]);
      final rawImage = CraftRawImageData.fromBytes(data, CraftImageType.RAW);

      expect(rawImage.isRawImage(), isTrue);
      expect(rawImage.getTypeCcitt(), equals(0));

      rawImage.setTypeCcitt(CraftRawImageData.ccittg4);
      expect(rawImage.getTypeCcitt(), equals(CraftRawImageData.ccittg4));
    });

    test('CCITT constants are defined correctly', () {
      expect(CraftRawImageData.ccittg4, equals(0x100));
      expect(CraftRawImageData.ccittg31d, equals(0x101));
      expect(CraftRawImageData.ccittg32d, equals(0x102));
      expect(CraftRawImageData.ccittBlackis1, equals(1));
      expect(CraftRawImageData.ccittEncodedbytealign, equals(2));
      expect(CraftRawImageData.ccittEndofline, equals(4));
      expect(CraftRawImageData.ccittEndofblock, equals(8));
    });
  });

  group('BmpImageData', () {
    test('creates from bytes with noHeader flag', () {
      final data = Uint8List.fromList([0x42, 0x4D, 0, 0]); // BM header
      final bmpImage = CraftBmpImageData.fromBytes(data);

      expect(bmpImage.isNoHeader(), isFalse);
      expect(bmpImage.originalType, equals(CraftImageType.BMP));
      expect(bmpImage.isRawImage(), isTrue);
    });

    test('creates with noHeader true', () {
      final data = Uint8List.fromList([0, 0, 0, 0]);
      final bmpImage = CraftBmpImageData.fromBytes(data, noHeader: true);

      expect(bmpImage.isNoHeader(), isTrue);
    });
  });

  group('TiffImageData', () {
    test('creates from bytes with default values', () {
      final data = Uint8List.fromList([0x4D, 0x4D, 0, 42]); // MM header
      final tiffImage = CraftTiffImageData.fromBytes(data);

      expect(tiffImage.originalType, equals(CraftImageType.TIFF));
      expect(tiffImage.isRawImage(), isTrue);
      expect(tiffImage.pageAt(), equals(1));
      expect(tiffImage.isDirect(), isFalse);
      expect(tiffImage.isRecoverFromImageError(), isFalse);
    });

    test('creates with custom page and options', () {
      final data = Uint8List.fromList([0x49, 0x49, 42, 0]); // II header
      final tiffImage = CraftTiffImageData.fromBytes(
        data,
        page: 3,
        direct: true,
        recoverFromImageError: true,
      );

      expect(tiffImage.pageAt(), equals(3));
      expect(tiffImage.isDirect(), isTrue);
      expect(tiffImage.isRecoverFromImageError(), isTrue);
    });

    test('can change original type', () {
      final data = Uint8List.fromList([0, 0, 0, 0]);
      final tiffImage = CraftTiffImageData.fromBytes(data);

      tiffImage.setOriginalType(CraftImageType.JPEG);
      expect(tiffImage.originalType, equals(CraftImageType.JPEG));
    });
  });
}
