import 'package:dpdf/src/kernel/pdf/xobject/pdf_x_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/io/image/image_data.dart';

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
      PdfName colorSpace;
      switch (image.colorEncodingComponentsNumber) {
        case 1:
          colorSpace = PdfName.deviceGray;
          break;
        case 3:
          colorSpace = PdfName.deviceRgb;
          break;
        case 4:
          colorSpace = PdfName.deviceCmyk;
          break;
        default:
          colorSpace = PdfName.deviceGray;
      }
      stream.put(PdfName.colorSpace, colorSpace);
    }

    if (image.decode != null) {
      stream.put(PdfName.decode, PdfArray.fromDoubles(image.decode!));
    }

    return stream;
  }
}
