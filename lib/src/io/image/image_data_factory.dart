import 'dart:typed_data';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/io/image/image_type_detector.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'package:dpdf/src/io/image/jpeg_image_data.dart';
import 'package:dpdf/src/io/image/jpeg_image_helper.dart';
import 'package:dpdf/src/io/image/png_image_data.dart';
import 'package:dpdf/src/io/image/png_image_helper.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

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
        ImageData image = PngImageData.fromBytes(bytes);
        PngImageHelper.processImage(image);
        return image;
      default:
        throw IoException(
            IoExceptionMessageConstant.imageFormatCannotBeRecognized);
    }
  }
}
