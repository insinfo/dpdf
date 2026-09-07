import 'package:dpdf/src/kernel/pdf/xobject/pdf_x_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/io/image/png_image_data.dart';

class CraftPdfImageXObject extends CraftPdfXObject {
  late final double _width;
  late final double _height;

  CraftPdfImageXObject(CraftImageData image) : super(_createPdfStream(image)) {
    _width = image.width;
    _height = image.height;
  }

  CraftPdfImageXObject._(CraftPdfStream stream, this._width, this._height)
      : super(stream);

  static Future<CraftPdfImageXObject> createFromStream(
      CraftPdfStream stream) async {
    CraftPdfNumber? w = await stream.numberEntry(CraftPdfName.width);
    double width = w?.getValue() ?? 0;
    CraftPdfNumber? h = await stream.numberEntry(CraftPdfName.height);
    double height = h?.getValue() ?? 0;
    return CraftPdfImageXObject._(stream, width, height);
  }

  @override
  double getWidth() => _width;

  @override
  double getHeight() => _height;

  static CraftPdfStream _createPdfStream(CraftImageData image) {
    final stream = CraftPdfStream.withBytes(image.getData());
    stream.put(CraftPdfName.type, CraftPdfName.xObject);
    stream.put(CraftPdfName.subtype, CraftPdfName.image);

    stream.put(CraftPdfName.width, CraftPdfNumber(image.width));
    stream.put(CraftPdfName.height, CraftPdfNumber(image.height));

    if (image.bpc != 0) {
      stream.put(
          CraftPdfName.bitsPerComponent, CraftPdfNumber(image.bpc.toDouble()));
    }

    if (image.filter != null) {
      stream.put(CraftPdfName.filter, CraftPdfName(image.filter!));
    }

    // Colorspace
    if (image.colorEncodingComponentsNumber != -1) {
      CraftPdfName colorSpaceName;
      switch (image.colorEncodingComponentsNumber) {
        case 1:
          colorSpaceName = CraftPdfName.deviceGray;
          break;
        case 3:
          colorSpaceName = CraftPdfName.deviceRgb;
          break;
        case 4:
          colorSpaceName = CraftPdfName.deviceCmyk;
          break;
        default:
          colorSpaceName = CraftPdfName.deviceGray;
      }

      if (image.colorPalette != null) {
        final colorSpace = CraftPdfArray();
        colorSpace.add(CraftPdfName.indexed);
        colorSpace.add(colorSpaceName);
        colorSpace.add(
            CraftPdfNumber((image.colorPalette!.length ~/ 3 - 1).toDouble()));
        colorSpace.add(CraftPdfStream.withBytes(image.colorPalette!));
        stream.put(CraftPdfName.colorSpace, colorSpace);
      } else {
        stream.put(CraftPdfName.colorSpace, colorSpaceName);
      }
    }

    if (image.decodeParms != null) {
      final parms = CraftPdfDictionary();
      image.decodeParms!.forEach((key, value) {
        if (value is int) {
          parms.put(CraftPdfName(key), CraftPdfNumber(value.toDouble()));
        } else if (value is double) {
          parms.put(CraftPdfName(key), CraftPdfNumber(value));
        } else if (value is String) {
          parms.put(CraftPdfName(key), CraftPdfName(value));
        }
      });
      stream.put(CraftPdfName.decodeParms, parms);
    }

    if (image is CraftPngImageData) {
      if (image.smask != null) {
        final mask = CraftPdfImageXObject(image.smask!);
        stream.put(CraftPdfName.sMask, mask.pdfRepresentation());
      }
      if (image.transparency != null) {
        stream.put(
            CraftPdfName.mask, CraftPdfArray.fromInts(image.transparency!));
      }
    }

    Object? mask = image.imageAttributes?["Mask"];
    if (mask is List<int>) {
      stream.put(CraftPdfName.mask, CraftPdfArray.fromInts(mask));
    }

    if (image.decode != null) {
      stream.put(CraftPdfName.decode, CraftPdfArray.fromDoubles(image.decode!));
    }

    return stream;
  }
}
