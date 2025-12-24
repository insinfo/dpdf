import 'dart:typed_data';
import 'image_data.dart';

/// GIF image data class that holds multiple frames.
class GifImageData {
  /// Logical height of the GIF canvas.
  double logicalHeight = 0;

  /// Logical width of the GIF canvas.
  double logicalWidth = 0;

  /// List of frames in the GIF.
  final List<ImageData> _frames = [];

  /// Raw data bytes.
  Uint8List? _data;

  /// Source URL.
  Uri? _url;

  /// Creates a GifImageData from a URL.
  GifImageData.fromUrl(Uri url) : _url = url;

  /// Creates a GifImageData from bytes.
  GifImageData.fromBytes(Uint8List data) : _data = data;

  /// Gets the logical height.
  double getLogicalHeight() => logicalHeight;

  /// Sets the logical height.
  void setLogicalHeight(double height) => logicalHeight = height;

  /// Gets the logical width.
  double getLogicalWidth() => logicalWidth;

  /// Sets the logical width.
  void setLogicalWidth(double width) => logicalWidth = width;

  /// Gets the list of frames.
  List<ImageData> getFrames() => _frames;

  /// Gets the raw data.
  Uint8List? getData() => _data;

  /// Gets the URL.
  Uri? getUrl() => _url;

  /// Adds a frame to the GIF.
  void addFrame(ImageData frame) => _frames.add(frame);

  /// Returns the number of frames.
  int get frameCount => _frames.length;
}
