import 'dart:typed_data';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'image_data.dart';

/// Raw image data class for images that need processing.
///
/// This class represents images that are stored in raw format,
/// including CCITT-encoded fax images.
class RawImageData extends ImageData {
  /// Pure two-dimensional encoding (Group 4)
  static const int ccittg4 = 0x100;

  /// Pure one-dimensional encoding (Group 3, 1-D)
  static const int ccittg31d = 0x101;

  /// Mixed one- and two-dimensional encoding (Group 3, 2-D)
  static const int ccittg32d = 0x102;

  /// A flag indicating whether 1-bits are to be interpreted as black pixels
  /// and 0-bits as white pixels.
  static const int ccittBlackis1 = 1;

  /// A flag indicating whether the filter expects extra 0-bits before each
  /// encoded line so that the line begins on a byte boundary.
  static const int ccittEncodedbytealign = 2;

  /// A flag indicating whether end-of-line bit patterns are required to be
  /// present in the encoding.
  static const int ccittEndofline = 4;

  /// A flag indicating whether the filter expects the encoded data to be
  /// terminated by an end-of-block pattern, overriding the Rows parameter.
  static const int ccittEndofblock = 8;

  /// CCITT encoding type
  int typeCcitt = 0;

  /// Creates a RawImageData from a URL.
  RawImageData.fromUrl(Uri url, ImageType type) : super.fromUrl(url, type);

  /// Creates a RawImageData from bytes.
  RawImageData.fromBytes(Uint8List data, ImageType type)
      : super.fromBytes(data, type);

  @override
  bool isRawImage() => true;

  /// Gets the CCITT type.
  int getTypeCcitt() => typeCcitt;

  /// Sets the CCITT type.
  void setTypeCcitt(int type) => typeCcitt = type;
}
