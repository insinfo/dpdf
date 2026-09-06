import '../pdf_stream.dart';
import '../../geom/affine_transform.dart';
import 'dart:math' as math;
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_array.dart';
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

  /// Calculates an [AffineTransform] that maps the coordinate system of a given
  /// [PdfFormXObject] to fit within a specified annotation bounding box.
  static Future<AffineTransform> calcAppearanceTransformToAnnotRect(
      PdfFormXObject xObject, Rectangle annotBBox) async {
    PdfArray? bBox = await xObject.getPdfObject().getAsArray(PdfName.bBox);
    if (bBox == null || bBox.size() != 4) {
      bBox = Rectangle(0, 0, 0, 0).toPdfArray();
      xObject.setBBox(Rectangle(0, 0, 0, 0));
    }
    
    // We need to await float values
    // Using a helper to get floats
    List<double> xObjBBox = await bBox.toDoubleArray();
    if (xObjBBox.length < 4) xObjBBox = [0, 0, 0, 0];

    PdfArray? xObjMatrix =
        await xObject.getPdfObject().getAsArray(PdfName.matrix);
    
    Rectangle transformedRect;
    if (xObjMatrix != null && xObjMatrix.size() == 6) {
      List<double> matrixArr = await xObjMatrix.toDoubleArray();
      
      // Points: (x1, y1), (x1, y2), (x2, y1), (x2, y2)
      // indices in BBox: 0=x1, 1=y1, 2=x2, 3=y2
      List<double> points = [
        xObjBBox[0], xObjBBox[1],
        xObjBBox[0], xObjBBox[3],
        xObjBBox[2], xObjBBox[1],
        xObjBBox[2], xObjBBox[3]
      ];
      
      AffineTransform t = AffineTransform.fromList(matrixArr);
      List<double> transformedPoints = t.transformPoints(points);
      
      double minX = double.maxFinite;
      double minY = double.maxFinite;
      double maxX = -double.maxFinite;
      double maxY = -double.maxFinite;
      
      for (int i = 0; i < transformedPoints.length; i += 2) {
        minX = math.min(minX, transformedPoints[i]);
        minY = math.min(minY, transformedPoints[i+1]);
        maxX = math.max(maxX, transformedPoints[i]);
        maxY = math.max(maxY, transformedPoints[i+1]);
      }
      
      transformedRect = Rectangle(minX, minY, maxX - minX, maxY - minY);
    } else {
      transformedRect = Rectangle(xObjBBox[0], xObjBBox[1], 
                                  xObjBBox[2] - xObjBBox[0], 
                                  xObjBBox[3] - xObjBBox[1]);
    }

    AffineTransform at = AffineTransform.getTranslateInstance(
        -transformedRect.getX(), -transformedRect.getY());
        
    double scaleX = transformedRect.getWidth() == 0
        ? 1
        : annotBBox.getWidth() / transformedRect.getWidth();
    double scaleY = transformedRect.getHeight() == 0
        ? 1
        : annotBBox.getHeight() / transformedRect.getHeight();
        
    at.preConcatenate(AffineTransform.getScaleInstance(scaleX, scaleY));
    at.preConcatenate(
        AffineTransform.getTranslateInstance(annotBBox.getX(), annotBBox.getY()));
        
    return at;
  }

  /// Sets the form matrix.
  void setFormMatrix(List<double> matrix) {
    if (matrix.length >= 6) {
      final arr = PdfArray.fromDoubles(matrix);
      getPdfObject().put(PdfName.matrix, arr);
    }
  }
}
