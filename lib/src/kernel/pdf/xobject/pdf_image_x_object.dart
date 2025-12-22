import 'package:dpdf/src/kernel/pdf/xobject/pdf_x_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/io/image/png_image_data.dart';

class PdfImageXObject extends PdfXObject {
  late final double _width;
  late final double _height;

  PdfImageXObject(ImageData image) : super(_createPdfStream(image)) {
    _width = image.width;
    _height = image.height;
  }

  PdfImageXObject._(PdfStream stream, this._width, this._height)
      : super(stream);

  static Future<PdfImageXObject> createFromStream(PdfStream stream) async {
    PdfNumber? w = await stream.getAsNumber(PdfName.width);
    double width = w?.getValue() ?? 0;
    PdfNumber? h = await stream.getAsNumber(PdfName.height);
    double height = h?.getValue() ?? 0;
    return PdfImageXObject._(stream, width, height);
  }

  @override
  double getWidth() => _width;

  @override
  double getHeight() => _height;

  static PdfStream _createPdfStream(ImageData image) {
    final stream = PdfStream.withBytes(image.getData());
    stream.put(PdfName.type, PdfName.xObject);
    stream.put(PdfName.subtype, PdfName.image);

    stream.put(PdfName.width, PdfNumber(image.width));
    stream.put(PdfName.height, PdfNumber(image.height));

    if (image.bpc != 0) {
      stream.put(PdfName.bitsPerComponent, PdfNumber(image.bpc.toDouble()));
    }

    if (image.filter != null) {
      stream.put(PdfName.filter, PdfName(image.filter!));
    }

    // Colorspace
    if (image.colorEncodingComponentsNumber != -1) {
      PdfName colorSpaceName;
      switch (image.colorEncodingComponentsNumber) {
        case 1:
          colorSpaceName = PdfName.deviceGray;
          break;
        case 3:
          colorSpaceName = PdfName.deviceRgb;
          break;
        case 4:
          colorSpaceName = PdfName.deviceCmyk;
          break;
        default:
          colorSpaceName = PdfName.deviceGray;
      }

      if (image.colorPalette != null) {
        final colorSpace = PdfArray();
        colorSpace.add(PdfName.indexed);
        colorSpace.add(colorSpaceName);
        colorSpace
            .add(PdfNumber((image.colorPalette!.length ~/ 3 - 1).toDouble()));
        colorSpace.add(PdfStream.withBytes(image.colorPalette!));
        stream.put(PdfName.colorSpace, colorSpace);
      } else {
        stream.put(PdfName.colorSpace, colorSpaceName);
      }
    }

    if (image.decodeParms != null) {
      final parms = PdfDictionary();
      image.decodeParms!.forEach((key, value) {
        if (value is int) {
          parms.put(PdfName(key), PdfNumber(value.toDouble()));
        } else if (value is double) {
          parms.put(PdfName(key), PdfNumber(value));
        } else if (value is String) {
          parms.put(PdfName(key), PdfName(value));
        }
      });
      stream.put(PdfName.decodeParms, parms);
    }

    if (image is PngImageData) {
      if (image.smask != null) {
        final mask = PdfImageXObject(image.smask!);
        stream.put(PdfName.sMask, mask.getPdfObject());
      }
      if (image.transparency != null) {
        stream.put(PdfName.mask, PdfArray.fromInts(image.transparency!));
      }
    }

    Object? mask = image.imageAttributes?["Mask"];
    if (mask is List<int>) {
      stream.put(PdfName.mask, PdfArray.fromInts(mask));
    }

    if (image.decode != null) {
      stream.put(PdfName.decode, PdfArray.fromDoubles(image.decode!));
    }

    return stream;
  }
}
