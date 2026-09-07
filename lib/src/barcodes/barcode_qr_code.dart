import '../kernel/colors/color.dart';
import '../kernel/geom/rectangle.dart';
import '../kernel/pdf/canvas/pdf_canvas.dart';

import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/xobject/pdf_form_x_object.dart';
import 'barcode_2d.dart';
import 'qrcode/byte_matrix.dart';
import 'qrcode/encode_hint_type.dart';
import 'qrcode/qr_code_writer.dart';

/// Draws a QR symbol as PDF vector modules.
class BarcodeQRCode extends Barcode2D {
  ByteMatrix? _bm;

  /// modifiers to change the way the barcode is create.
  Map<EncodeHintType, dynamic>? _hints;

  String? _code;

  /// Creates the QR barcode.
  /// [code] - the text to be encoded
  /// [hints] - barcode hints. See #setHints for description.
  BarcodeQRCode([String? code, Map<EncodeHintType, dynamic>? hints]) {
    _code = code;
    _hints = hints;
    if (_code != null) {
      regenerate();
    }
  }

  /// Gets the current data.
  /// Returns the encoded data
  String? getCode() {
    return _code;
  }

  /// Sets the data to be encoded by the barcode.
  /// Replaces the text payload; the default byte codec is ISO-8859-1.
  /// [code] - The data to encode
  void setCode(String code) {
    _code = code;
    regenerate();
  }

  /// Returns modifiers to change the way the barcode is created.
  Map<EncodeHintType, dynamic>? getHints() {
    return _hints;
  }

  /// [hints] - modifiers to change the way the barcode is created. They can be EncodeHintType.ERROR_CORRECTION
  /// ERROR_CORRECTION selects L, M, Q or H; CHARACTER_SET selects the byte codec.
  /// The current encoder supports ISO-8859-1 and UTF-8 byte conversion.
  /// UTF-8 segments include ECI assignment 26.
  /// The default value is ISO-8859-1.
  void setHints(Map<EncodeHintType, dynamic> hints) {
    _hints = hints;
    regenerate();
  }

  /// Regenerates barcode after changes in hints or code.
  void regenerate() {
    if (_code != null) {
      try {
        QRCodeWriter qc = QRCodeWriter();
        _bm = qc.encode(_code!, 1, 1, _hints);
      } catch (ex) {
        throw ArgumentError(ex.toString());
      }
    }
  }

  /// Gets the size of the barcode grid
  @override
  Rectangle? getBarcodeSize() {
    return Rectangle(
        0, 0, _bm!.getWidth().toDouble(), _bm!.getHeight().toDouble());
  }

  /// Gets the barcode size
  /// [moduleSize] - The module size
  /// Returns The size of the barcode
  Rectangle getBarcodeSizeWithModuleSize(double moduleSize) {
    return Rectangle(
        0, 0, _bm!.getWidth() * moduleSize, _bm!.getHeight() * moduleSize);
  }

  @override
  Rectangle placeBarcode(PdfCanvas canvas, Color? foreground) {
    return placeBarcodeWithModuleSide(
        canvas, foreground, Barcode2D.DEFAULT_MODULE_SIZE);
  }

  /// Places the barcode in a [PdfCanvas].
  ///
  /// The barcode is always placed at coordinates (0, 0). Use the
  /// translation matrix to move it elsewhere.
  ///
  /// [canvas] - the [PdfCanvas] where the barcode will be placed
  /// [foreground] - the foreground color. It can be [null]
  /// [moduleSide] - the size of the square grid cell
  /// Returns the dimensions the barcode occupies
  Rectangle placeBarcodeWithModuleSide(
      PdfCanvas canvas, Color? foreground, double moduleSide) {
    if (!moduleSide.isFinite || moduleSide <= 0) {
      throw ArgumentError.value(
          moduleSide, 'moduleSide', 'Module size must be finite and positive');
    }
    final matrix = _bm!;
    if (foreground != null) canvas.setFillColor(foreground);
    for (var row = 0; row < matrix.getHeight(); row++) {
      var column = 0;
      while (column < matrix.getWidth()) {
        if (matrix.get(column, row) != 0) {
          column++;
          continue;
        }
        final start = column;
        do {
          column++;
        } while (column < matrix.getWidth() && matrix.get(column, row) == 0);
        canvas.rectangle(
            start * moduleSide,
            (matrix.getHeight() - 1 - row) * moduleSide,
            (column - start) * moduleSide,
            moduleSide);
      }
    }
    canvas.fill();
    return getBarcodeSizeWithModuleSize(moduleSide);
  }

  /// Creates a PdfFormXObject with the barcode.
  /// [foreground] - the color of the pixels. It can be [null]
  /// Returns the XObject.
  @override
  Future<PdfFormXObject> createFormXObject(PdfDocument document,
      [Color? foreground]) async {
    return createFormXObjectWithModuleSize(
        foreground, Barcode2D.DEFAULT_MODULE_SIZE, document);
  }

  /// Creates a PdfFormXObject with the barcode.
  /// [foreground] - The color of the pixels. It can be [null]
  /// [moduleSize] - The size of the pixels.
  /// [document] - The document
  /// Returns the XObject.
  Future<PdfFormXObject> createFormXObjectWithModuleSize(
      Color? foreground, double moduleSize, PdfDocument document) async {
    PdfFormXObject xObject = PdfFormXObject(Rectangle(0, 0, 0, 0));
    PdfCanvas canvas = await PdfCanvas.fromFormXObject(xObject, document);
    Rectangle rect = placeBarcodeWithModuleSide(canvas, foreground, moduleSize);
    xObject.setBBox(rect);
    return xObject;
  }
}
