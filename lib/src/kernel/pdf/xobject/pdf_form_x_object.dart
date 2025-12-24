import '../pdf_stream.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_resources.dart';
import '../../geom/rectangle.dart';
import 'pdf_x_object.dart';

class PdfFormXObject extends PdfXObject {
  PdfResources? _resources;

  PdfFormXObject(Rectangle bBox) : super(PdfStream()) {
    getPdfObject().put(PdfName.type, PdfName.xObject);
    getPdfObject().put(PdfName.subtype, PdfName.form);
    getPdfObject().put(PdfName.bBox, bBox.toPdfArray());
  }

  PdfFormXObject.fromStream(PdfStream pdfStream) : super(pdfStream) {
    if (!getPdfObject().containsKey(PdfName.subtype)) {
      getPdfObject().put(PdfName.subtype, PdfName.form);
    }
  }

  Future<PdfResources> getResources() async {
    if (_resources == null) {
      PdfDictionary? resourcesDict =
          await getPdfObject().getAsDictionary(PdfName.resources);
      if (resourcesDict == null) {
        resourcesDict = PdfDictionary();
        getPdfObject().put(PdfName.resources, resourcesDict);
      }
      _resources = PdfResources(resourcesDict);
    }
    return _resources!;
  }

  @override
  double getWidth() {
    // TODO: Implement BBox parsing to get actual width
    return 0;
  }

  @override
  double getHeight() {
    // TODO: Implement BBox parsing to get actual height
    return 0;
  }
}
