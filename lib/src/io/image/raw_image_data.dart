import 'dart:typed_data';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'image_data.dart';

/// Raw image data class for images that need processing.
///
/// This class represents images that are stored in raw format,
/// including CCITT-encoded fax images.
class CraftRawImageData extends CraftImageData {
  /// Pure two-dimensional encoding (Group 4)
  static const int ccittg4 = 0x100;

  /// Pure one-dimensional encoding (Group 3, 1-D)
  static const int ccittg31d = 0x101;

  /// Mixed one- and two-dimensional encoding (Group 3, 2-D)
  static const int ccittg32d = 0x102;

  /// Interprets set bits as black when this flag is enabled.
  /// and 0-bits as white pixels.
  static const int ccittBlackis1 = 1;

  /// Requests zero padding before each
  /// encoded row to maintain byte alignment.
  static const int ccittEncodedbytealign = 2;

  /// Requires end-of-line markers to be
  /// present in the encoding.
  static const int ccittEndofline = 4;

  /// Controls whether the encoded stream must be
  /// terminated by an end-of-block pattern, overriding the Rows parameter.
  static const int ccittEndofblock = 8;

  /// CCITT encoding type
  int typeCcitt = 0;

  /// Creates a RawImageData from a URL.
  CraftRawImageData.fromUrl(Uri url, CraftImageType type)
      : super.fromUrl(url, type);

  /// Creates a RawImageData from bytes.
  CraftRawImageData.fromBytes(Uint8List data, CraftImageType type)
      : super.fromBytes(data, type);

  @override
  bool isRawImage() => true;

  /// Gets the CCITT type.
  int getTypeCcitt() => typeCcitt;

  /// Sets the CCITT type.
  void setTypeCcitt(int type) => typeCcitt = type;
}
