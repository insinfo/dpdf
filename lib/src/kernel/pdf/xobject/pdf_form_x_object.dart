import '../pdf_stream.dart';
import '../../geom/affine_transform.dart';
import 'dart:math' as math;
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_array.dart';
import '../pdf_resources.dart';
import '../../geom/rectangle.dart';
import 'pdf_x_object.dart';

class CraftPdfFormXObject extends CraftPdfXObject {
  CraftPdfResources? _resources;
  CraftRectangle? _bBoxCache;

  CraftPdfFormXObject(CraftRectangle bBox) : super(CraftPdfStream()) {
    pdfRepresentation().put(CraftPdfName.type, CraftPdfName.xObject);
    pdfRepresentation().put(CraftPdfName.subtype, CraftPdfName.form);
    pdfRepresentation().put(CraftPdfName.bBox, bBox.toPdfArray());
    _bBoxCache = bBox;
  }

  CraftPdfFormXObject.fromStream(CraftPdfStream pdfStream) : super(pdfStream) {
    if (!pdfRepresentation().containsKey(CraftPdfName.subtype)) {
      pdfRepresentation().put(CraftPdfName.subtype, CraftPdfName.form);
    }
  }

  Future<CraftPdfResources> resourceDirectory() async {
    if (_resources == null) {
      CraftPdfDictionary? resourcesDict =
          await pdfRepresentation().dictionaryEntry(CraftPdfName.resources);
      if (resourcesDict == null) {
        resourcesDict = CraftPdfDictionary();
        pdfRepresentation().put(CraftPdfName.resources, resourcesDict);
      }
      _resources = CraftPdfResources(resourcesDict);
    }
    return _resources!;
  }

  /// Gets the BBox rectangle.
  Future<CraftRectangle?> getBBox() async {
    if (_bBoxCache != null) {
      return _bBoxCache;
    }

    final bBoxArray = await pdfRepresentation().arrayEntry(CraftPdfName.bBox);
    if (bBoxArray == null || bBoxArray.size() < 4) {
      return null;
    }

    final x1 = await bBoxArray.numberEntry(0);
    final y1 = await bBoxArray.numberEntry(1);
    final x2 = await bBoxArray.numberEntry(2);
    final y2 = await bBoxArray.numberEntry(3);

    if (x1 == null || y1 == null || x2 == null || y2 == null) {
      return null;
    }

    final x = x1.doubleValue();
    final y = y1.doubleValue();
    final width = x2.doubleValue() - x;
    final height = y2.doubleValue() - y;

    _bBoxCache = CraftRectangle(x, y, width, height);
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
  void setBBox(CraftRectangle rectangle) {
    pdfRepresentation().put(CraftPdfName.bBox, rectangle.toPdfArray());
    _bBoxCache = rectangle;
  }

  /// Calculates an [AffineTransform] that maps the coordinate system of a given
  /// [PdfFormXObject] to fit within a specified annotation bounding box.
  static Future<CraftAffineTransform> calcAppearanceTransformToAnnotRect(
      CraftPdfFormXObject xObject, CraftRectangle annotBBox) async {
    CraftPdfArray? bBox =
        await xObject.pdfRepresentation().arrayEntry(CraftPdfName.bBox);
    if (bBox == null || bBox.size() != 4) {
      bBox = CraftRectangle(0, 0, 0, 0).toPdfArray();
      xObject.setBBox(CraftRectangle(0, 0, 0, 0));
    }

    // We need to await float values
    // Using a helper to get floats
    List<double> xObjBBox = await bBox.toDoubleArray();
    if (xObjBBox.length < 4) xObjBBox = [0, 0, 0, 0];

    CraftPdfArray? xObjMatrix =
        await xObject.pdfRepresentation().arrayEntry(CraftPdfName.matrix);

    CraftRectangle transformedRect;
    if (xObjMatrix != null && xObjMatrix.size() == 6) {
      List<double> matrixArr = await xObjMatrix.toDoubleArray();

      // Points: (x1, y1), (x1, y2), (x2, y1), (x2, y2)
      // indices in BBox: 0=x1, 1=y1, 2=x2, 3=y2
      List<double> points = [
        xObjBBox[0],
        xObjBBox[1],
        xObjBBox[0],
        xObjBBox[3],
        xObjBBox[2],
        xObjBBox[1],
        xObjBBox[2],
        xObjBBox[3]
      ];

      CraftAffineTransform t = CraftAffineTransform.fromList(matrixArr);
      List<double> transformedPoints = t.transformPoints(points);

      double minX = double.maxFinite;
      double minY = double.maxFinite;
      double maxX = -double.maxFinite;
      double maxY = -double.maxFinite;

      for (int i = 0; i < transformedPoints.length; i += 2) {
        minX = math.min(minX, transformedPoints[i]);
        minY = math.min(minY, transformedPoints[i + 1]);
        maxX = math.max(maxX, transformedPoints[i]);
        maxY = math.max(maxY, transformedPoints[i + 1]);
      }

      transformedRect = CraftRectangle(minX, minY, maxX - minX, maxY - minY);
    } else {
      transformedRect = CraftRectangle(xObjBBox[0], xObjBBox[1],
          xObjBBox[2] - xObjBBox[0], xObjBBox[3] - xObjBBox[1]);
    }

    CraftAffineTransform at = CraftAffineTransform.getTranslateInstance(
        -transformedRect.getX(), -transformedRect.getY());

    double scaleX = transformedRect.getWidth() == 0
        ? 1
        : annotBBox.getWidth() / transformedRect.getWidth();
    double scaleY = transformedRect.getHeight() == 0
        ? 1
        : annotBBox.getHeight() / transformedRect.getHeight();

    at.preConcatenate(CraftAffineTransform.getScaleInstance(scaleX, scaleY));
    at.preConcatenate(CraftAffineTransform.getTranslateInstance(
        annotBBox.getX(), annotBBox.getY()));

    return at;
  }

  /// Sets the form matrix.
  void setFormMatrix(List<double> matrix) {
    if (matrix.length >= 6) {
      final arr = CraftPdfArray.fromDoubles(matrix);
      pdfRepresentation().put(CraftPdfName.matrix, arr);
    }
  }
}
