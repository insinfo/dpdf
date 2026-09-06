import 'dart:typed_data';

import '../kernel/colors/color.dart';
import '../kernel/font/pdf_font.dart';
import '../kernel/geom/rectangle.dart';
import '../kernel/pdf/canvas/pdf_canvas.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/exceptions/pdf_exception.dart';

import 'barcode_1d.dart';

/// EAN and UPC retail symbols, including two- and five-digit supplements.
class CraftBarcodeEAN extends CraftBarcode1D {
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

  /// Uses the supplied typeface or the document's configured default.
  factory CraftBarcodeEAN(CraftPdfDocument document, [CraftPdfFont? font]) {
    final resolvedFont = font ?? document.defaultTypeface();
    if (resolvedFont == null) {
      throw CraftPdfException(
          'Could not create default font for barcode. Please provide a font explicitly.');
    }
    return CraftBarcodeEAN._internal(document, resolvedFont);
  }

  CraftBarcodeEAN._internal(CraftPdfDocument document, CraftPdfFont font)
      : super(document) {
    this.x = 0.8;
    this.font = font;
    this.size = 8;
    this.baseline = size;
    this.barHeight = size * 3;
    this.guardBars = true;
    this.codeType = EAN13;
    this.code = "";
  }

  static List<int> _digits(String text, [int? length]) {
    if (length != null && text.length != length) {
      throw FormatException('Retail symbol requires $length digits');
    }
    final digits = text.codeUnits.map((unit) => unit - 48).toList();
    if (digits.any((digit) => digit < 0 || digit > 9)) {
      throw const FormatException('Retail symbol contains a nondigit');
    }
    return digits;
  }

  /// Computes the modulo-ten digit for the preceding payload.
  static int calculateEANParity(String code) {
    final digits = _digits(code).reversed.toList();
    var sum = 0;
    for (var index = 0; index < digits.length; index++) {
      sum += digits[index] * (index.isEven ? 3 : 1);
    }
    return (-sum) % 10;
  }

  /// Compresses a twelve-digit UPC-A when its zero runs permit UPC-E.
  static String? convertUPCAtoUPCE(String text) {
    if (text.length != 12 || !RegExp(r'^[01][0-9]{11}$').hasMatch(text))
      return null;
    final manufacturer = text.substring(1, 6);
    final product = text.substring(6, 11);
    String? payload;
    if (manufacturer.endsWith('00') &&
        int.parse(manufacturer[2]) <= 2 &&
        product.startsWith('00')) {
      payload =
          manufacturer.substring(0, 2) + product.substring(2) + manufacturer[2];
    } else if (manufacturer.endsWith('00') &&
        int.parse(manufacturer[2]) >= 3 &&
        product.startsWith('000')) {
      payload = manufacturer.substring(0, 3) + product.substring(3) + '3';
    } else if (manufacturer.endsWith('0') &&
        manufacturer[3] != '0' &&
        product.startsWith('0000')) {
      payload = manufacturer.substring(0, 4) + product[4] + '4';
    } else if (manufacturer[4] != '0' &&
        product.startsWith('0000') &&
        int.parse(product[4]) >= 5) {
      payload = manufacturer + product[4];
    }
    return payload == null ? null : text[0] + payload + text[11];
  }

  static Iterable<int> _segment(int digit, int parity) =>
      parity == EVEN ? BARS[digit].reversed : BARS[digit];

  static Uint8List _retail(List<int> left, List<int> right, List<int> parity) =>
      Uint8List.fromList([
        1,
        1,
        1,
        for (var index = 0; index < left.length; index++)
          ..._segment(left[index], parity[index]),
        1,
        1,
        1,
        1,
        1,
        for (final digit in right) ...BARS[digit],
        1,
        1,
        1,
      ]);

  /// Alternating dark/light run widths, starting with a dark guard.
  static Uint8List getBarsEAN13(String code) {
    final digits = _digits(code, 13);
    return _retail(
        digits.sublist(1, 7), digits.sublist(7), PARITY13[digits.first]);
  }

  static Uint8List getBarsEAN8(String code) {
    final digits = _digits(code, 8);
    return _retail(
        digits.sublist(0, 4), digits.sublist(4), [ODD, ODD, ODD, ODD]);
  }

  static Uint8List getBarsUPCE(String code) {
    final digits = _digits(code, 8);
    if (digits.first > 1)
      throw const FormatException('UPC-E number system must be zero or one');
    final parity = PARITYE[digits.last];
    return Uint8List.fromList([
      1,
      1,
      1,
      for (var index = 0; index < 6; index++)
        ..._segment(digits[index + 1], parity[index] ^ digits.first),
      1,
      1,
      1,
      1,
      1,
      1,
    ]);
  }

  static Uint8List _supplement(List<int> digits, List<int> parity) =>
      Uint8List.fromList([
        1,
        1,
        2,
        for (var index = 0; index < digits.length; index++) ...[
          if (index > 0) ...[1, 1],
          ..._segment(digits[index], parity[index]),
        ],
      ]);

  static Uint8List getBarsSupplemental2(String code) {
    final digits = _digits(code, 2);
    return _supplement(digits, PARITY2[int.parse(code) % 4]);
  }

  static Uint8List getBarsSupplemental5(String code) {
    final digits = _digits(code, 5);
    var check = 0;
    for (var index = 0; index < digits.length; index++) {
      check += digits[index] * (index.isEven ? 3 : 9);
    }
    return _supplement(digits, PARITY5[check % 10]);
  }

  (Uint8List, List<int>) _pattern() => switch (codeType) {
        EAN13 => (getBarsEAN13(code), GUARD_EAN13),
        EAN8 => (getBarsEAN8(code), GUARD_EAN8),
        UPCA => (getBarsEAN13('0$code'), GUARD_UPCA),
        UPCE => (getBarsUPCE(code), GUARD_UPCE),
        SUPP2 => (getBarsSupplemental2(code), GUARD_EMPTY),
        SUPP5 => (getBarsSupplemental5(code), GUARD_EMPTY),
        _ => throw CraftPdfException(
            'Retail symbol type $codeType is not supported'),
      };

  bool get _outsideFirst =>
      codeType == EAN13 || codeType == UPCA || codeType == UPCE;
  bool get _outsideLast => codeType == UPCA || codeType == UPCE;
  double _digitWidth(int index) => font?.getWidthPoint(code[index], size) ?? 0;
  double get _leftTextWidth => _outsideFirst ? _digitWidth(0) : 0;

  @override
  CraftRectangle getBarcodeSize() {
    final (runs, _) = _pattern();
    final moduleCount = runs.fold<int>(0, (sum, run) => sum + run);
    final textHeight = font == null
        ? 0.0
        : baseline > 0
            ? baseline - getDescender()
            : size - baseline;
    final extraRight = _outsideLast ? _digitWidth(code.length - 1) : 0.0;
    return CraftRectangle(0, 0, moduleCount * x + _leftTextWidth + extraRight,
        barHeight + textHeight);
  }

  @override
  Future<CraftRectangle> placeBarcode(CraftPdfCanvas canvas,
      CraftColor? barColor, CraftColor? textColor) async {
    final bounds = getBarcodeSize();
    final (runs, guards) = _pattern();
    final textY = font == null
        ? 0.0
        : baseline > 0
            ? -getDescender()
            : barHeight - baseline;
    final barY = font != null && baseline > 0 ? textY + baseline : 0.0;
    final extension =
        font != null && baseline > 0 && guardBars ? baseline / 2 : 0.0;
    final left = _leftTextWidth;
    var cursor = left;
    if (barColor != null) canvas.setFillColor(barColor);
    for (var index = 0; index < runs.length; index++) {
      final width = runs[index] * x;
      if (index.isEven) {
        final descent = guards.contains(index) ? extension : 0.0;
        canvas.rectangle(
            cursor, barY - descent, width - inkSpreading, barHeight + descent);
      }
      cursor += width;
    }
    canvas.fill();
    if (font == null) return bounds;
    if (textColor != null) canvas.setFillColor(textColor);
    canvas.beginText();
    await canvas.setFontAndSize(font!, size);
    for (var index = 0; index < code.length; index++) {
      double position;
      if (_outsideFirst && index == 0) {
        position = 0;
      } else if (_outsideLast && index == code.length - 1) {
        position = cursor;
      } else {
        final center = switch (codeType) {
          EAN13 || UPCE => TEXTPOS_EAN13[index - 1],
          UPCA => TEXTPOS_EAN13[index],
          EAN8 => TEXTPOS_EAN8[index],
          _ => 7.5 + index * 9,
        };
        position = left + center * x - _digitWidth(index) / 2;
      }
      canvas.setTextMatrixSimple(position, textY);
      canvas.showText(code[index]);
    }
    canvas.endText();
    return bounds;
  }
}
