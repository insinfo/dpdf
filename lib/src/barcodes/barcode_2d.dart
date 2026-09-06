import '../kernel/colors/color.dart';
import '../kernel/geom/rectangle.dart';
import '../kernel/pdf/canvas/pdf_canvas.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/xobject/pdf_form_x_object.dart';

/// This is a class that is used to implement the logic common to all 2D barcodes.
///
/// A 2D barcode is a barcode with two dimensions; this means that
/// data can be encoded vertically and horizontally.
abstract class Barcode2D {
  static const double DEFAULT_MODULE_SIZE = 1;

  /// Gets the maximum area that the barcode and the text, if any, will occupy.
  ///
  /// The lower left corner is always (0, 0).
  Rectangle? getBarcodeSize();

  /// Places the barcode in a [PdfCanvas].
  ///
  /// The barcode is always placed at coordinates (0, 0). Use the translation matrix to move it elsewhere.
  ///
  /// [canvas] - the [PdfCanvas] where the barcode will be placed
  /// [foreground] - the foreground color. It can be [null]
  /// Returns the dimensions the barcode occupies
  Rectangle? placeBarcode(PdfCanvas canvas, Color? foreground);

  /// Creates a [PdfFormXObject] with the barcode.
  ///
  /// Default foreground color will be used.
  Future<PdfFormXObject> createFormXObject(PdfDocument document,
      [Color? foreground]);
}
