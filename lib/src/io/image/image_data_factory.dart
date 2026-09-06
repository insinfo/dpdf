import 'dart:typed_data';
import 'dart:io';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/io/image/image_type_detector.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'package:dpdf/src/io/image/jpeg_image_data.dart';
import 'package:dpdf/src/io/image/jpeg_image_helper.dart';
import 'package:dpdf/src/io/image/png_image_data.dart';
import 'package:dpdf/src/io/image/png_image_helper.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

import 'package:dpdf/src/io/image/raw_image_data.dart';
import 'package:dpdf/src/io/image/bmp_image_data.dart';
import 'package:dpdf/src/io/image/bmp_image_helper.dart';
import 'package:dpdf/src/io/image/gif_image_data.dart';
import 'package:dpdf/src/io/image/gif_image_helper.dart';
import 'package:dpdf/src/io/image/jbig2_image_data.dart';
import 'package:dpdf/src/io/image/jbig2_image_helper.dart';
import 'package:dpdf/src/io/image/tiff_image_data.dart';
import 'package:dpdf/src/io/image/tiff_image_helper.dart';

class ImageDataFactory {
  ImageDataFactory._();

  static ImageData create(Uint8List bytes) {
    ImageType type = ImageTypeDetector.detectImageType(bytes);
    switch (type) {
      case ImageType.JPEG:
        ImageData image = JpegImageData.fromBytes(bytes);
        JpegImageHelper.processImage(image);
        return image;
      case ImageType.PNG:
        ImageData imagePng = PngImageData.fromBytes(bytes);
        PngImageHelper.processImage(imagePng);
        return imagePng;
      case ImageType.BMP:
        ImageData imageBmp = BmpImageData.fromBytes(bytes);
        BmpImageHelper.processImage(imageBmp);
        return imageBmp;
      case ImageType.GIF:
        GifImageData gifData = GifImageData.fromBytes(bytes);
        GifImageHelper.processImage(gifData);
        if (gifData.getFrames().isEmpty) {
          throw IoException(IoExceptionMessageConstant.gifImageException);
        }
        return gifData.getFrames()[0];
      case ImageType.JBIG2:
        ImageData imageJbig2 = Jbig2ImageData.fromBytes(bytes, 1);
        Jbig2ImageHelper.processImage(imageJbig2);
        return imageJbig2;
      case ImageType.TIFF:
        ImageData imageTiff = TiffImageData.fromBytes(bytes);
        TiffImageHelper.processImage(imageTiff);
        return imageTiff;
      default:
        throw IoException(
            IoExceptionMessageConstant.imageFormatCannotBeRecognized);
    }
  }

  static ImageData createRawImage(Uint8List? bytes) {
    return RawImageData.fromBytes(bytes ?? Uint8List(0), ImageType.NONE);
  }

  /// Creates an ImageData from a URL (local file or HTTP/HTTPS).
  static Future<ImageData> createFromUrl(Uri url) async {
    Uint8List bytes;
    if (url.scheme == 'file' || url.scheme.isEmpty) {
      final file = File.fromUri(url);
      bytes = await file.readAsBytes();
    } else if (url.scheme == 'http' || url.scheme == 'https') {
      final client = HttpClient();
      try {
        final request = await client.getUrl(url);
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw IoException('Failed to download image: ${response.statusCode}');
        }
        bytes = await _readResponseBytes(response);
      } finally {
        client.close();
      }
    } else {
      throw IoException('Unsupported URL scheme: ${url.scheme}');
    }

    final imageData = create(bytes);
    imageData.url = url;
    return imageData;
  }

  static Future<Uint8List> _readResponseBytes(
      HttpClientResponse response) async {
    final chunks = <List<int>>[];
    await for (final chunk in response) {
      chunks.add(chunk);
    }
    final totalLength = chunks.fold(0, (sum, chunk) => sum + chunk.length);
    final bytes = Uint8List(totalLength);
    int offset = 0;
    for (final chunk in chunks) {
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return bytes;
  }
}
