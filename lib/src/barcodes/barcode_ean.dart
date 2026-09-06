import 'dart:typed_data';

import '../kernel/colors/color.dart';
import '../kernel/font/pdf_font.dart';
import '../kernel/geom/rectangle.dart';
import '../kernel/pdf/canvas/pdf_canvas.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/exceptions/pdf_exception.dart';

import 'barcode_1d.dart';

/// The implementation of the barcode EAN.
///
/// The International Article Number (also known as European Article Number or EAN) is a standard describing a barcode
/// symbology and numbering system used in global trade to identify a specific retail product type, in a specific
/// packaging configuration, from a specific manufacturer
class BarcodeEAN extends Barcode1D {
  /// A type of barcode
  static const int EAN13 = 1;

  /// A type of barcode
  static const int EAN8 = 2;

  /// A type of barcode
  static const int UPCA = 3;

  /// A type of barcode
  static const int UPCE = 4;

  /// A type of barcode
  static const int SUPP2 = 5;

  /// A type of barcode
  static const int SUPP5 = 6;

  /// The bar positions that are guard bars.
  static final List<int> GUARD_EMPTY = [];

  /// The bar positions that are guard bars.
  static final List<int> GUARD_UPCA = [0, 2, 4, 6, 28, 30, 52, 54, 56, 58];

  /// The bar positions that are guard bars.
  static final List<int> GUARD_EAN13 = [0, 2, 28, 30, 56, 58];

  /// The bar positions that are guard bars.
  static final List<int> GUARD_EAN8 = [0, 2, 20, 22, 40, 42];

  /// The bar positions that are guard bars.
  static final List<int> GUARD_UPCE = [0, 2, 28, 30, 32];

  /// The x coordinates to place the text.
  static final List<double> TEXTPOS_EAN13 = [
    6.5,
    13.5,
    20.5,
    27.5,
    34.5,
    41.5,
    53.5,
    60.5,
    67.5,
    74.5,
    81.5,
    88.5
  ];

  /// The x coordinates to place the text.
  static final List<double> TEXTPOS_EAN8 = [
    6.5,
    13.5,
    20.5,
    27.5,
    39.5,
    46.5,
    53.5,
    60.5
  ];

  /// The basic bar widths.
  static const List<List<int>> BARS = [
    [3, 2, 1, 1],
    [2, 2, 2, 1],
    [2, 1, 2, 2],
    [1, 4, 1, 1],
    [1, 1, 3, 2],
    [1, 2, 3, 1],
    [1, 1, 1, 4],
    [1, 3, 1, 2],
    [1, 2, 1, 3],
    [3, 1, 1, 2]
  ];

  /// The total number of bars for EAN13.
  static const int TOTALBARS_EAN13 = 11 + 12 * 4;

  /// The total number of bars for EAN8.
  static const int TOTALBARS_EAN8 = 11 + 8 * 4;

  /// The total number of bars for UPCE.
  static const int TOTALBARS_UPCE = 9 + 6 * 4;

  /// The total number of bars for supplemental 2.
  static const int TOTALBARS_SUPP2 = 13;

  /// The total number of bars for supplemental 5.
  static const int TOTALBARS_SUPP5 = 31;

  /// Marker for odd parity.
  static const int ODD = 0;

  /// Marker for even parity.
  static const int EVEN = 1;

  /// Sequence of parities to be used with EAN13.
  static const List<List<int>> PARITY13 = [
    [ODD, ODD, ODD, ODD, ODD, ODD],
    [ODD, ODD, EVEN, ODD, EVEN, EVEN],
    [ODD, ODD, EVEN, EVEN, ODD, EVEN],
    [ODD, ODD, EVEN, EVEN, EVEN, ODD],
    [ODD, EVEN, ODD, ODD, EVEN, EVEN],
    [ODD, EVEN, EVEN, ODD, ODD, EVEN],
    [ODD, EVEN, EVEN, EVEN, ODD, ODD],
    [ODD, EVEN, ODD, EVEN, ODD, EVEN],
    [ODD, EVEN, ODD, EVEN, EVEN, ODD],
    [ODD, EVEN, EVEN, ODD, EVEN, ODD]
  ];

  /// Sequence of parities to be used with supplemental 2.
  static const List<List<int>> PARITY2 = [
    [ODD, ODD],
    [ODD, EVEN],
    [EVEN, ODD],
    [EVEN, EVEN]
  ];

  /// Sequence of parities to be used with supplemental 2.
  static const List<List<int>> PARITY5 = [
    [EVEN, EVEN, ODD, ODD, ODD],
    [EVEN, ODD, EVEN, ODD, ODD],
    [EVEN, ODD, ODD, EVEN, ODD],
    [EVEN, ODD, ODD, ODD, EVEN],
    [ODD, EVEN, EVEN, ODD, ODD],
    [ODD, ODD, EVEN, EVEN, ODD],
    [ODD, ODD, ODD, EVEN, EVEN],
    [ODD, EVEN, ODD, EVEN, ODD],
    [ODD, EVEN, ODD, ODD, EVEN],
    [ODD, ODD, EVEN, ODD, EVEN]
  ];

  /// Sequence of parities to be used with UPCE.
  static const List<List<int>> PARITYE = [
    [EVEN, EVEN, EVEN, ODD, ODD, ODD],
    [EVEN, EVEN, ODD, EVEN, ODD, ODD],
    [EVEN, EVEN, ODD, ODD, EVEN, ODD],
    [EVEN, EVEN, ODD, ODD, ODD, EVEN],
    [EVEN, ODD, EVEN, EVEN, ODD, ODD],
    [EVEN, ODD, ODD, EVEN, EVEN, ODD],
    [EVEN, ODD, ODD, ODD, EVEN, EVEN],
    [EVEN, ODD, EVEN, ODD, EVEN, ODD],
    [EVEN, ODD, EVEN, ODD, ODD, EVEN],
    [EVEN, ODD, ODD, EVEN, ODD, EVEN]
  ];

  /// Creates new [BarcodeEAN].
  ///
  /// To generate the font the [PdfDocument.getDefaultFont] will be implicitly called.
  /// If you want to use this barcode in PDF/A documents, please consider using
  /// [BarcodeEAN](PdfDocument document, PdfFont font).
  factory BarcodeEAN(PdfDocument document, [PdfFont? font]) {
    final resolvedFont = font ?? document.getDefaultFont();
    if (resolvedFont == null) {
      throw PdfException(
          'Could not create default font for barcode. Please provide a font explicitly.');
    }
    return BarcodeEAN._internal(document, resolvedFont);
  }

  BarcodeEAN._internal(PdfDocument document, PdfFont font) : super(document) {
    this.x = 0.8;
    this.font = font;
    this.size = 8;
    this.baseline = size;
    this.barHeight = size * 3;
    this.guardBars = true;
    this.codeType = EAN13;
    this.code = "";
  }

  /// Calculates the EAN parity character.
  static int calculateEANParity(String code) {
    int mul = 3;
    int total = 0;
    for (int k = code.length - 1; k >= 0; --k) {
      int n = code.codeUnitAt(k) - 48; // '0'
      total += mul * n;
      mul ^= 2;
    }
    return (10 - (total % 10)) % 10;
  }

  /// Converts an UPCA code into an UPCE code.
  ///
  /// If the code can not be converted a [null] is returned.
  static String? convertUPCAtoUPCE(String text) {
    if (text.length != 12 || !(text.startsWith("0") || text.startsWith("1"))) {
      return null;
    }
    if (text.substring(3, 6) == "000" ||
        text.substring(3, 6) == "100" ||
        text.substring(3, 6) == "200") {
      if (text.substring(6, 8) == "00") {
        return text.substring(0, 1) +
            text.substring(1, 3) +
            text.substring(8, 11) +
            text.substring(3, 4) +
            text.substring(11);
      }
    } else {
      if (text.substring(4, 6) == "00") {
        if (text.substring(6, 9) == "000") {
          return text.substring(0, 1) +
              text.substring(1, 4) +
              text.substring(9, 11) +
              "3" +
              text.substring(11);
        }
      } else {
        if (text.substring(5, 6) == "0") {
          if (text.substring(6, 10) == "0000") {
            return text.substring(0, 1) +
                text.substring(1, 5) +
                text.substring(10, 11) +
                "4" +
                text.substring(11);
          }
        } else {
          if (text.codeUnitAt(10) >= 53) {
            // '5'
            if (text.substring(6, 10) == "0000") {
              return text.substring(0, 1) +
                  text.substring(1, 6) +
                  text.substring(10, 11) +
                  text.substring(11);
            }
          }
        }
      }
    }
    return null;
  }

  /// Creates the bars for the barcode EAN13 and UPCA.
  static Uint8List getBarsEAN13(String _code) {
    List<int> code = List<int>.filled(_code.length, 0);
    for (int k = 0; k < code.length; ++k) {
      code[k] = _code.codeUnitAt(k) - 48; // '0'
    }
    Uint8List bars = Uint8List(TOTALBARS_EAN13);
    int pb = 0;
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    List<int> sequence = PARITY13[code[0]];
    for (int k = 0; k < sequence.length; ++k) {
      int c = code[k + 1];
      List<int> stripes = BARS[c];
      if (sequence[k] == ODD) {
        bars[pb++] = stripes[0];
        bars[pb++] = stripes[1];
        bars[pb++] = stripes[2];
        bars[pb++] = stripes[3];
      } else {
        bars[pb++] = stripes[3];
        bars[pb++] = stripes[2];
        bars[pb++] = stripes[1];
        bars[pb++] = stripes[0];
      }
    }
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    for (int k = 7; k < 13; ++k) {
      int c = code[k];
      List<int> stripes = BARS[c];
      bars[pb++] = stripes[0];
      bars[pb++] = stripes[1];
      bars[pb++] = stripes[2];
      bars[pb++] = stripes[3];
    }
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    return bars;
  }

  /// Creates the bars for the barcode EAN8.
  static Uint8List getBarsEAN8(String _code) {
    List<int> code = List<int>.filled(_code.length, 0);
    for (int k = 0; k < code.length; ++k) {
      code[k] = _code.codeUnitAt(k) - 48;
    }
    Uint8List bars = Uint8List(TOTALBARS_EAN8);
    int pb = 0;
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    for (int k = 0; k < 4; ++k) {
      int c = code[k];
      List<int> stripes = BARS[c];
      bars[pb++] = stripes[0];
      bars[pb++] = stripes[1];
      bars[pb++] = stripes[2];
      bars[pb++] = stripes[3];
    }
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    for (int k = 4; k < 8; ++k) {
      int c = code[k];
      List<int> stripes = BARS[c];
      bars[pb++] = stripes[0];
      bars[pb++] = stripes[1];
      bars[pb++] = stripes[2];
      bars[pb++] = stripes[3];
    }
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    return bars;
  }

  /// Creates the bars for the barcode UPCE.
  static Uint8List getBarsUPCE(String _code) {
    List<int> code = List<int>.filled(_code.length, 0);
    for (int k = 0; k < code.length; ++k) {
      code[k] = _code.codeUnitAt(k) - 48;
    }
    Uint8List bars = Uint8List(TOTALBARS_UPCE);
    bool flip = (code[0] != 0);
    int pb = 0;
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    List<int> sequence = PARITYE[code[code.length - 1]];
    for (int k = 1; k < code.length - 1; ++k) {
      int c = code[k];
      List<int> stripes = BARS[c];
      if (sequence[k - 1] == (flip ? EVEN : ODD)) {
        bars[pb++] = stripes[0];
        bars[pb++] = stripes[1];
        bars[pb++] = stripes[2];
        bars[pb++] = stripes[3];
      } else {
        bars[pb++] = stripes[3];
        bars[pb++] = stripes[2];
        bars[pb++] = stripes[1];
        bars[pb++] = stripes[0];
      }
    }
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 1;
    return bars;
  }

  /// Creates the bars for the barcode supplemental 2.
  static Uint8List getBarsSupplemental2(String _code) {
    List<int> code = List<int>.filled(2, 0);
    for (int k = 0; k < code.length; ++k) {
      code[k] = _code.codeUnitAt(k) - 48;
    }
    Uint8List bars = Uint8List(TOTALBARS_SUPP2);
    int pb = 0;
    int parity = (code[0] * 10 + code[1]) % 4;
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 2;
    List<int> sequence = PARITY2[parity];
    for (int k = 0; k < sequence.length; ++k) {
      if (k == 1) {
        bars[pb++] = 1;
        bars[pb++] = 1;
      }
      int c = code[k];
      List<int> stripes = BARS[c];
      if (sequence[k] == ODD) {
        bars[pb++] = stripes[0];
        bars[pb++] = stripes[1];
        bars[pb++] = stripes[2];
        bars[pb++] = stripes[3];
      } else {
        bars[pb++] = stripes[3];
        bars[pb++] = stripes[2];
        bars[pb++] = stripes[1];
        bars[pb++] = stripes[0];
      }
    }
    return bars;
  }

  /// Creates the bars for the barcode supplemental 5.
  static Uint8List getBarsSupplemental5(String _code) {
    List<int> code = List<int>.filled(5, 0);
    for (int k = 0; k < code.length; ++k) {
      code[k] = _code.codeUnitAt(k) - 48;
    }
    Uint8List bars = Uint8List(TOTALBARS_SUPP5);
    int pb = 0;
    int parity =
        (((code[0] + code[2] + code[4]) * 3) + ((code[1] + code[3]) * 9)) % 10;
    bars[pb++] = 1;
    bars[pb++] = 1;
    bars[pb++] = 2;
    List<int> sequence = PARITY5[parity];
    for (int k = 0; k < sequence.length; ++k) {
      if (k != 0) {
        bars[pb++] = 1;
        bars[pb++] = 1;
      }
      int c = code[k];
      List<int> stripes = BARS[c];
      if (sequence[k] == ODD) {
        bars[pb++] = stripes[0];
        bars[pb++] = stripes[1];
        bars[pb++] = stripes[2];
        bars[pb++] = stripes[3];
      } else {
        bars[pb++] = stripes[3];
        bars[pb++] = stripes[2];
        bars[pb++] = stripes[1];
        bars[pb++] = stripes[0];
      }
    }
    return bars;
  }

  @override
  Rectangle getBarcodeSize() {
    double width = 0;
    double height = barHeight;
    if (font != null) {
      if (baseline <= 0) {
        height += -baseline + size;
      } else {
        height += baseline - getDescender();
      }
    }
    switch (codeType) {
      case EAN13:
        {
          width = x * (11 + 12 * 7);
          if (font != null) {
            width += font!.getWidthPoint(code.substring(0, 1), size);
          }
          break;
        }

      case EAN8:
        {
          width = x * (11 + 8 * 7);
          break;
        }

      case UPCA:
        {
          width = x * (11 + 12 * 7);
          if (font != null) {
            width += font!.getWidthPoint(code.substring(0, 1), size) +
                font!.getWidthPoint(code.substring(11, 12), size);
          }
          break;
        }

      case UPCE:
        {
          width = x * (9 + 6 * 7);
          if (font != null) {
            width += font!.getWidthPoint(code.substring(0, 1), size) +
                font!.getWidthPoint(code.substring(7, 8), size);
          }
          break;
        }

      case SUPP2:
        {
          width = x * (6 + 2 * 7);
          break;
        }

      case SUPP5:
        {
          width = x * (4 + 5 * 7 + 4 * 2);
          break;
        }

      default:
        {
          throw PdfException("Invalid code type");
        }
    }
    return Rectangle(0, 0, width, height);
  }

  @override
  Future<Rectangle> placeBarcode(
      PdfCanvas canvas, Color? barColor, Color? textColor) async {
    Rectangle rect = getBarcodeSize();
    double barStartX = 0;
    double barStartY = 0;
    double textStartY = 0;
    if (font != null) {
      if (baseline <= 0) {
        textStartY = barHeight - baseline;
      } else {
        textStartY = -getDescender();
        barStartY = textStartY + baseline;
      }
    }
    switch (codeType) {
      case EAN13:
      case UPCA:
      case UPCE:
        {
          if (font != null) {
            barStartX += font!.getWidthPoint(code.substring(0, 1), size);
          }
          break;
        }
    }
    Uint8List bars;
    List<int> guard = GUARD_EMPTY;
    switch (codeType) {
      case EAN13:
        {
          bars = getBarsEAN13(code);
          guard = GUARD_EAN13;
          break;
        }

      case EAN8:
        {
          bars = getBarsEAN8(code);
          guard = GUARD_EAN8;
          break;
        }

      case UPCA:
        {
          bars = getBarsEAN13("0" + code);
          guard = GUARD_UPCA;
          break;
        }

      case UPCE:
        {
          bars = getBarsUPCE(code);
          guard = GUARD_UPCE;
          break;
        }

      case SUPP2:
        {
          bars = getBarsSupplemental2(code);
          break;
        }

      case SUPP5:
        {
          bars = getBarsSupplemental5(code);
          break;
        }

      default:
        {
          throw PdfException("Invalid code type");
        }
    }
    double keepBarX = barStartX;
    bool print = true;
    double gd = 0;
    if (font != null && baseline > 0 && guardBars) {
      gd = baseline / 2;
    }
    if (barColor != null) {
      canvas.setFillColor(barColor);
    }
    for (int k = 0; k < bars.length; ++k) {
      double w = bars[k] * x;
      if (print) {
        if (guard.contains(k)) {
          canvas.rectangle(
              barStartX, barStartY - gd, w - inkSpreading, barHeight + gd);
        } else {
          canvas.rectangle(barStartX, barStartY, w - inkSpreading, barHeight);
        }
      }
      print = !print;
      barStartX += w;
    }
    canvas.fill();
    if (font != null) {
      if (textColor != null) {
        canvas.setFillColor(textColor);
      }
      canvas.beginText();
      await canvas.setFontAndSize(font!, size);
      switch (codeType) {
        case EAN13:
          {
            canvas.setTextMatrixSimple(0, textStartY);
            canvas.showText(code.substring(0, 1));
            for (int k = 1; k < 13; ++k) {
              String c = code.substring(k, k + 1);
              double len = font!.getWidthPoint(c, size);
              double pX = keepBarX + TEXTPOS_EAN13[k - 1] * x - len / 2;
              canvas.setTextMatrixSimple(pX, textStartY);
              canvas.showText(c);
            }
            break;
          }

        case EAN8:
          {
            for (int k = 0; k < 8; ++k) {
              String c = code.substring(k, k + 1);
              double len = font!.getWidthPoint(c, size);
              double pX = TEXTPOS_EAN8[k] * x - len / 2;
              canvas.setTextMatrixSimple(pX, textStartY);
              canvas.showText(c);
            }
            break;
          }

        case UPCA:
          {
            canvas.setTextMatrixSimple(0, textStartY);
            canvas.showText(code.substring(0, 1));
            for (int k = 1; k < 11; ++k) {
              String c = code.substring(k, k + 1);
              double len = font!.getWidthPoint(c, size);
              double pX = keepBarX + TEXTPOS_EAN13[k] * x - len / 2;
              canvas.setTextMatrixSimple(pX, textStartY);
              canvas.showText(c);
            }
            canvas.setTextMatrixSimple(
                keepBarX + x * (11 + 12 * 7), textStartY);
            canvas.showText(code.substring(11, 12));
            break;
          }

        case UPCE:
          {
            canvas.setTextMatrixSimple(0, textStartY);
            canvas.showText(code.substring(0, 1));
            for (int k = 1; k < 7; ++k) {
              String c = code.substring(k, k + 1);
              double len = font!.getWidthPoint(c, size);
              double pX = keepBarX + TEXTPOS_EAN13[k - 1] * x - len / 2;
              canvas.setTextMatrixSimple(pX, textStartY);
              canvas.showText(c);
            }
            canvas.setTextMatrixSimple(keepBarX + x * (9 + 6 * 7), textStartY);
            canvas.showText(code.substring(7, 8));
            break;
          }

        case SUPP2:
        case SUPP5:
          {
            for (int k = 0; k < code.length; ++k) {
              String c = code.substring(k, k + 1);
              double len = font!.getWidthPoint(c, size);
              double pX = (7.5 + (9 * k)) * x - len / 2;
              canvas.setTextMatrixSimple(pX, textStartY);
              canvas.showText(c);
            }
            break;
          }
      }
      canvas.endText();
    }
    return rect;
  }
}
