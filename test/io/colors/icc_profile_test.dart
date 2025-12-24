import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/io/colors/icc_profile.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';

void main() {
  group('IccProfile', () {
    test('getIccColorSpaceName extracts color space', () {
      // Create minimal ICC header with 'RGB ' color space at offset 16
      final data = Uint8List(128);
      data[16] = 0x52; // R
      data[17] = 0x47; // G
      data[18] = 0x42; // B
      data[19] = 0x20; // space

      final colorSpace = IccProfile.getIccColorSpaceName(data);
      expect(colorSpace, equals('RGB '));
    });

    test('getIccDeviceClass extracts device class', () {
      // Create minimal ICC header with device class at offset 12
      final data = Uint8List(128);
      data[12] = 0x6D; // m
      data[13] = 0x6E; // n
      data[14] = 0x74; // t
      data[15] = 0x72; // r

      final deviceClass = IccProfile.getIccDeviceClass(data);
      expect(deviceClass, equals('mntr'));
    });

    test('getIccNumberOfComponents returns correct count', () {
      final data = Uint8List(128);
      // RGB colorspace
      data[16] = 0x52; // R
      data[17] = 0x47; // G
      data[18] = 0x42; // B
      data[19] = 0x20; // space

      expect(IccProfile.getIccNumberOfComponents(data), equals(3));

      // GRAY colorspace
      data[16] = 0x47; // G
      data[17] = 0x52; // R
      data[18] = 0x41; // A
      data[19] = 0x59; // Y

      expect(IccProfile.getIccNumberOfComponents(data), equals(1));

      // CMYK colorspace
      data[16] = 0x43; // C
      data[17] = 0x4D; // M
      data[18] = 0x59; // Y
      data[19] = 0x4B; // K

      expect(IccProfile.getIccNumberOfComponents(data), equals(4));
    });

    test('getInstance throws for invalid profile', () {
      final badData = Uint8List(50);
      expect(
          () => IccProfile.getInstance(badData), throwsA(isA<IoException>()));
    });

    test('getInstance validates acsp signature', () {
      final data = Uint8List(128);
      // Missing 'acsp' signature
      expect(() => IccProfile.getInstance(data), throwsA(isA<IoException>()));
    });

    test('getInstance creates valid profile', () {
      // Create valid ICC profile header
      final data = Uint8List(128);
      // Size
      data[0] = 0;
      data[1] = 0;
      data[2] = 0;
      data[3] = 128;
      // Device class at 12
      data[12] = 0x6D; // m
      data[13] = 0x6E; // n
      data[14] = 0x74; // t
      data[15] = 0x72; // r
      // Color space RGB at 16
      data[16] = 0x52; // R
      data[17] = 0x47; // G
      data[18] = 0x42; // B
      data[19] = 0x20; // space
      // 'acsp' signature at 36
      data[36] = 0x61; // a
      data[37] = 0x63; // c
      data[38] = 0x73; // s
      data[39] = 0x70; // p

      final profile = IccProfile.getInstance(data);
      expect(profile.getNumComponents(), equals(3));
      expect(profile.getData(), equals(data));
    });
  });
}
