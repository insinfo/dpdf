import 'dart:typed_data';
import '../exceptions/io_exception.dart';
import '../exceptions/io_exception_message_constant.dart';

/// Class used to represent the International Color Consortium profile.
class IccProfile {
  /// Raw ICC profile data.
  Uint8List? data;

  /// Number of color components in the profile.
  int numComponents = 0;

  /// Color space tag to number of components mapping.
  static final Map<String, int> _cstags = {
    'XYZ ': 3,
    'Lab ': 3,
    'Luv ': 3,
    'YCbr': 3,
    'Yxy ': 3,
    'RGB ': 3,
    'GRAY': 1,
    'HSV ': 3,
    'HLS ': 3,
    'CMYK': 4,
    'CMY ': 3,
    '2CLR': 2,
    '3CLR': 3,
    '4CLR': 4,
    '5CLR': 5,
    '6CLR': 6,
    '7CLR': 7,
    '8CLR': 8,
    '9CLR': 9,
    'ACLR': 10,
    'BCLR': 11,
    'CCLR': 12,
    'DCLR': 13,
    'ECLR': 14,
    'FCLR': 15,
  };

  /// Private constructor.
  IccProfile._();

  /// Construct an ICC profile from the passed byte[], using the passed number of components.
  static IccProfile getInstance(Uint8List data, [int? numComponentsHint]) {
    if (data.length < 128 ||
        data[36] != 0x61 ||
        data[37] != 0x63 ||
        data[38] != 0x73 ||
        data[39] != 0x70) {
      throw IoException(IoExceptionMessageConstant.invalidIccProfile);
    }

    final icc = IccProfile._();
    icc.data = data;

    final nc = getIccNumberOfComponents(data) ?? 0;
    icc.numComponents = nc;

    // Validate component count if hint provided
    if (numComponentsHint != null && nc != numComponentsHint) {
      throw IoException(
          '${IoExceptionMessageConstant.invalidIccProfile}: ICC profile contains $nc components while image data contains $numComponentsHint');
    }

    return icc;
  }

  /// Get the color space name of the ICC profile found in the data.
  static String getIccColorSpaceName(Uint8List data) {
    if (data.length < 20) {
      throw IoException(IoExceptionMessageConstant.invalidIccProfile);
    }
    return String.fromCharCodes(data.sublist(16, 20));
  }

  /// Get the device class of the ICC profile found in the data.
  static String getIccDeviceClass(Uint8List data) {
    if (data.length < 16) {
      throw IoException(IoExceptionMessageConstant.invalidIccProfile);
    }
    return String.fromCharCodes(data.sublist(12, 16));
  }

  /// Get the number of color components of the ICC profile found in the data.
  static int? getIccNumberOfComponents(Uint8List data) {
    final colorSpace = getIccColorSpaceName(data);
    return _cstags[colorSpace];
  }

  /// Get the ICC color profile data.
  Uint8List? getData() => data;

  /// Get the number of color components in the profile.
  int getNumComponents() => numComponents;
}
