import '../kernel/colors/color.dart';
import '../kernel/font/pdf_font.dart';
import '../kernel/geom/rectangle.dart';
import '../kernel/pdf/canvas/pdf_canvas.dart';

import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/xobject/pdf_form_x_object.dart';
import '../io/font/font_program.dart';

/// Base class for the barcode types that have 1D representation.
///
/// This means all data is encoded in the width of the bars. And the height of the bars is constant.
abstract class Barcode1D {
  /// Constant that defines left alignment.
  static const int ALIGN_LEFT = 1;

  /// Constant that defines right alignment.
  static const int ALIGN_RIGHT = 2;

  /// Constant that defines center alignment.
  static const int ALIGN_CENTER = 3;

  PdfDocument document;

  /// The minimum bar width.
  double x = 0;

  /// The bar multiplier for wide bars or the distance between bars for Postnet and Planet.
  double n = 0;

  /// The text font. [null] if no text.
  PdfFont? font;

  /// The size of the text or the height of the shorter bar in Postnet.
  double size = 0;

  /// If positive, the text distance under the bars.
  /// If positive, the text distance under the bars. If zero or negative,
  /// the text distance above the bars.
  double baseline = 0;

  /// The height of the bars.
  double barHeight = 0;

  /// The text alignment.
  int textAlignment = 0;

  /// The optional checksum generation.
  bool generateChecksum = false;

  /// Shows the generated checksum in the the text.
  bool checksumText = false;

  /// Show the start and stop character '*' in the text for the barcode 39 or 'ABCD' for codabar.
  bool startStopText = false;

  /// Generates extended barcode 39.
  bool extended = false;

  /// The code to generate.
  String code = "";

  /// Show the guard bars for barcode EAN.
  bool guardBars = false;

  /// The code type.
  int codeType = 0;

  /// The ink spreading.
  double inkSpreading = 0;

  /// The alternate text to be used, if present.
  String? altText;

  /// Creates new [Barcode1D] instance.
  ///
  /// [document] - The document
  Barcode1D(this.document);

  /// Gets the minimum bar width.
  double getX() => x;

  /// Sets the minimum bar width.
  void setX(double x) => this.x = x;

  /// Gets the bar multiplier for wide bars.
  double getN() => n;

  /// Sets the bar multiplier for wide bars.
  void setN(double n) => this.n = n;

  /// Gets the text font.
  ///
  /// Returns the text font. [null] if no text.
  PdfFont? getFont() => font;

  /// Sets the text font.
  ///
  /// [font] - the text font. Set to [null] to suppress any text
  void setFont(PdfFont? font) => this.font = font;

  /// Gets the size of the text.
  double getSize() => size;

  /// Sets the size of the text.
  void setSize(double size) => this.size = size;

  /// Gets the text baseline.
  double getBaseline() => baseline;

  /// Sets the text baseline.
  void setBaseline(double baseline) => this.baseline = baseline;

  /// Gets the height of the bars.
  double getBarHeight() => barHeight;

  /// Sets the height of the bars.
  void setBarHeight(double barHeight) => this.barHeight = barHeight;

  /// Gets the text alignment.
  int getTextAlignment() => textAlignment;

  /// Sets the text alignment.
  void setTextAlignment(int textAlignment) =>
      this.textAlignment = textAlignment;

  /// Gets the optional checksum generation.
  bool isGenerateChecksum() => generateChecksum;

  /// Sets the optional checksum generation.
  void setGenerateChecksum(bool generateChecksum) =>
      this.generateChecksum = generateChecksum;

  /// Gets the property to show the generated checksum in the the text.
  bool isChecksumText() => checksumText;

  /// Sets the property to show the generated checksum in the the text.
  void setChecksumText(bool checksumText) => this.checksumText = checksumText;

  /// Gets the property to show the start and stop character '*' in the text for the barcode 39.
  bool isStartStopText() => startStopText;

  /// Sets the property to show the start and stop character '*' in the text for the barcode 39.
  void setStartStopText(bool startStopText) =>
      this.startStopText = startStopText;

  /// Gets the property to generate extended barcode 39.
  bool isExtended() => extended;

  /// Sets the property to generate extended barcode 39.
  void setExtended(bool extended) => this.extended = extended;

  /// Gets the code to generate.
  String getCode() => code;

  /// Sets the code to generate.
  void setCode(String code) => this.code = code;

  /// Gets the property to show the guard bars for barcode EAN.
  bool isGuardBars() => guardBars;

  /// Sets the property to show the guard bars for barcode EAN.
  void setGuardBars(bool guardBars) => this.guardBars = guardBars;

  /// Gets the code type.
  int getCodeType() => codeType;

  /// Sets the code type.
  void setCodeType(int codeType) => this.codeType = codeType;

  /// Gets the maximum area that the barcode and the text, if any, will occupy.
  ///
  /// The lower left corner is always (0, 0).
  Rectangle? getBarcodeSize();

  /// Places the barcode in a [PdfCanvas].
  ///
  /// The barcode is always placed at coordinates (0, 0). Use the translation matrix to move it elsewhere.
  ///
  /// [canvas] - the [PdfCanvas] where the barcode will be placed
  /// [barColor] - the color of the bars. It can be [null]
  /// [textColor] - the color of the text. It can be [null]
  /// Returns the dimensions the barcode occupies
  Future<Rectangle?> placeBarcode(
      PdfCanvas canvas, Color? barColor, Color? textColor);

  /// Gets the amount of ink spreading.
  double getInkSpreading() => inkSpreading;

  /// Sets the amount of ink spreading.
  ///
  /// This value will be subtracted to the width of each bar.
  /// The actual value will depend on the ink and the printing medium.
  void setInkSpreading(double inkSpreading) => this.inkSpreading = inkSpreading;

  /// Gets the alternate text.
  String? getAltText() => altText;

  /// Sets the alternate text.
  ///
  /// If present, this text will be used instead of the text derived from the supplied code.
  void setAltText(String? altText) => this.altText = altText;

  /// Creates a [PdfFormXObject] with the barcode.
  ///
  /// Default bar color and text color will be used.
  Future<PdfFormXObject> createFormXObject(PdfDocument document,
      [Color? barColor, Color? textColor]) async {
    PdfFormXObject xObject = PdfFormXObject(Rectangle(0, 0, 0, 0));
    Rectangle? rect = await placeBarcode(
        await PdfCanvas.fromFormXObject(xObject, document),
        barColor,
        textColor);
    if (rect != null) {
      xObject.setBBox(rect);
    }
    return xObject;
  }

  /// Make the barcode occupy the specified width.
  ///
  /// Usually this is achieved by adjusting bar widths.
  void fitWidth(double width) {
    setX(x * width / (getBarcodeSize()?.getWidth() ?? 1));
  }

  /// Gets the descender value of the font.
  double getDescender() {
    if (font == null) return 0;
    double sizeCoefficient = FontProgram.convertTextSpaceToGlyphSpace(size);
    return font!.getFontProgram()!.getFontMetrics().getTypoDescender() *
        sizeCoefficient;
  }
}
