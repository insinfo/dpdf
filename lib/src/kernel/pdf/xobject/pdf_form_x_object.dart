import '../pdf_stream.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_array.dart';
import '../pdf_number.dart';
import '../pdf_resources.dart';
import '../../geom/rectangle.dart';
import 'pdf_x_object.dart';

class PdfFormXObject extends PdfXObject {
  PdfResources? _resources;
  Rectangle? _bBoxCache;

  PdfFormXObject(Rectangle bBox) : super(PdfStream()) {
    getPdfObject().put(PdfName.type, PdfName.xObject);
    getPdfObject().put(PdfName.subtype, PdfName.form);
    getPdfObject().put(PdfName.bBox, bBox.toPdfArray());
    _bBoxCache = bBox;
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

  /// Gets the BBox rectangle.
  Future<Rectangle?> getBBox() async {
    if (_bBoxCache != null) {
      return _bBoxCache;
    }

    final bBoxArray = await getPdfObject().getAsArray(PdfName.bBox);
    if (bBoxArray == null || bBoxArray.size() < 4) {
      return null;
    }

    final x1 = await bBoxArray.getAsNumber(0);
    final y1 = await bBoxArray.getAsNumber(1);
    final x2 = await bBoxArray.getAsNumber(2);
    final y2 = await bBoxArray.getAsNumber(3);

    if (x1 == null || y1 == null || x2 == null || y2 == null) {
      return null;
    }

    final x = x1.doubleValue();
    final y = y1.doubleValue();
    final width = x2.doubleValue() - x;
    final height = y2.doubleValue() - y;

    _bBoxCache = Rectangle(x, y, width, height);
    return _bBoxCache;
  }

  @override
  double getWidth() {
    // Sync version - returns cached value or 0
    // Use getWidthAsync for async version with parsing
    return _bBoxCache?.getWidth() ?? 0;
  }

  /// Gets the width asynchronously by parsing BBox if needed.
  Future<double> getWidthAsync() async {
    final bbox = await getBBox();
    return bbox?.getWidth() ?? 0;
  }

  @override
  double getHeight() {
    // Sync version - returns cached value or 0
    // Use getHeightAsync for async version with parsing
    return _bBoxCache?.getHeight() ?? 0;
  }

  /// Gets the height asynchronously by parsing BBox if needed.
  Future<double> getHeightAsync() async {
    final bbox = await getBBox();
    return bbox?.getHeight() ?? 0;
  }

  /// Sets the BBox for the form XObject.
  void setBBox(Rectangle rectangle) {
    getPdfObject().put(PdfName.bBox, rectangle.toPdfArray());
    _bBoxCache = rectangle;
  }

  /// Sets the form matrix.
  void setFormMatrix(List<double> matrix) {
    if (matrix.length >= 6) {
      final arr = PdfArray();
      for (int i = 0; i < 6; i++) {
        arr.add(PdfNumber(matrix[i]));
      }
      getPdfObject().put(PdfName.matrix, arr);
    }
  }
}
