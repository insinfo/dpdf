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

/// Reads the parts of an ICC profile header a conformance check needs.
///
/// [IccProfile.getInstance] throws on the first defect, which is right for a
/// decoder and wrong for a validator: a validator has to say what is wrong
/// rather than stop. These helpers describe the header instead.
class IccProfileHeader {
  /// Profile size declared by the first four bytes of the header.
  final int declaredSize;

  /// Actual number of bytes available.
  final int actualSize;

  /// Device class, e.g. `prtr` for an output device.
  final String deviceClass;

  /// Data colour space, e.g. `RGB ` or `CMYK`.
  final String colourSpace;

  /// Major version, from the high byte of the version field.
  final int majorVersion;

  /// Minor version, from the high nibble of the next byte.
  final int minorVersion;

  const IccProfileHeader({
    required this.declaredSize,
    required this.actualSize,
    required this.deviceClass,
    required this.colourSpace,
    required this.majorVersion,
    required this.minorVersion,
  });

  /// Number of colour components the data colour space implies, or null when
  /// the space is not one ICC defines.
  int? get numberOfComponents => IccProfile._cstags[colourSpace];

  /// Device classes that describe an output condition, which is what an
  /// output intent names.
  static const Set<String> outputDeviceClasses = {'prtr', 'mntr'};

  /// Every device class ICC defines.
  static const Set<String> knownDeviceClasses = {
    'scnr',
    'mntr',
    'prtr',
    'link',
    'spac',
    'abst',
    'nmcl',
  };

  /// Parses the 128 byte header of [data], or returns null when there is no
  /// header to read.
  static IccProfileHeader? parse(Uint8List data) {
    if (data.length < 128) return null;
    return IccProfileHeader(
      declaredSize:
          (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3],
      actualSize: data.length,
      deviceClass: String.fromCharCodes(data.sublist(12, 16)),
      colourSpace: String.fromCharCodes(data.sublist(16, 20)),
      majorVersion: data[8],
      minorVersion: (data[9] >> 4) & 0x0F,
    );
  }

  /// True when the header carries the `acsp` signature ICC requires at offset
  /// 36. Without it the bytes are not an ICC profile at all.
  static bool hasSignature(Uint8List data) =>
      data.length >= 40 &&
      data[36] == 0x61 &&
      data[37] == 0x63 &&
      data[38] == 0x73 &&
      data[39] == 0x70;

  /// The defects of this header, in English, one per problem. An empty list
  /// means the header is sound.
  List<String> defects() {
    final problems = <String>[];
    if (declaredSize < 128) {
      problems.add('the header declares a profile size of $declaredSize '
          'bytes, which is smaller than the 128 byte header itself');
    } else if (declaredSize > actualSize) {
      problems.add('the header declares $declaredSize bytes but only '
          '$actualSize are present, so the profile is truncated');
    }
    if (!knownDeviceClasses.contains(deviceClass)) {
      problems.add('the device class "$deviceClass" is not one ICC defines');
    } else if (!outputDeviceClasses.contains(deviceClass)) {
      problems.add('the device class is "$deviceClass"; an output intent has '
          'to name an output condition, so only prtr and mntr fit');
    }
    if (numberOfComponents == null) {
      problems.add('the data colour space "$colourSpace" is not one ICC '
          'defines');
    }
    if (majorVersion < 2 || majorVersion > 5) {
      problems.add('the profile declares version $majorVersion.$minorVersion, '
          'which no ICC specification uses');
    }
    return problems;
  }

  @override
  String toString() => 'IccProfileHeader($deviceClass, $colourSpace, '
      'v$majorVersion.$minorVersion, $declaredSize bytes)';
}
