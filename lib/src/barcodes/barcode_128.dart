import 'linear_symbol_painter.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import '../kernel/colors/color.dart';
import '../kernel/font/pdf_font.dart';
import '../kernel/geom/rectangle.dart';
import '../kernel/pdf/canvas/pdf_canvas.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/exceptions/pdf_exception.dart';

import 'barcode_1d.dart';
import 'exceptions/barcodes_exception_message_constant.dart';

/// BarCode 128 is a high-density linear barcode symbology defined in ISO/IEC 15417:2007.
///
/// It is used for alphanumeric or numeric-only barcodes. It can encode all 128 characters of ASCII
class CraftBarcode128 extends CraftBarcode1D {
  /// A type of barcode
  static const int CODE128 = 1;

  /// A type of barcode
  static const int CODE128_UCC = 2;

  /// A type of barcode
  static const int CODE128_RAW = 3;

  /// The bars to generate the code.
  static const List<List<int>> BARS = [
    [2, 1, 2, 2, 2, 2],
    [2, 2, 2, 1, 2, 2],
    [2, 2, 2, 2, 2, 1],
    [1, 2, 1, 2, 2, 3],
    [1, 2, 1, 3, 2, 2],
    [1, 3, 1, 2, 2, 2],
    [1, 2, 2, 2, 1, 3],
    [1, 2, 2, 3, 1, 2],
    [1, 3, 2, 2, 1, 2],
    [2, 2, 1, 2, 1, 3],
    [2, 2, 1, 3, 1, 2],
    [2, 3, 1, 2, 1, 2],
    [1, 1, 2, 2, 3, 2],
    [1, 2, 2, 1, 3, 2],
    [1, 2, 2, 2, 3, 1],
    [1, 1, 3, 2, 2, 2],
    [1, 2, 3, 1, 2, 2],
    [1, 2, 3, 2, 2, 1],
    [2, 2, 3, 2, 1, 1],
    [2, 2, 1, 1, 3, 2],
    [2, 2, 1, 2, 3, 1],
    [2, 1, 3, 2, 1, 2],
    [2, 2, 3, 1, 1, 2],
    [3, 1, 2, 1, 3, 1],
    [3, 1, 1, 2, 2, 2],
    [3, 2, 1, 1, 2, 2],
    [3, 2, 1, 2, 2, 1],
    [3, 1, 2, 2, 1, 2],
    [3, 2, 2, 1, 1, 2],
    [3, 2, 2, 2, 1, 1],
    [2, 1, 2, 1, 2, 3],
    [2, 1, 2, 3, 2, 1],
    [2, 3, 2, 1, 2, 1],
    [1, 1, 1, 3, 2, 3],
    [1, 3, 1, 1, 2, 3],
    [1, 3, 1, 3, 2, 1],
    [1, 1, 2, 3, 1, 3],
    [1, 3, 2, 1, 1, 3],
    [1, 3, 2, 3, 1, 1],
    [2, 1, 1, 3, 1, 3],
    [2, 3, 1, 1, 1, 3],
    [2, 3, 1, 3, 1, 1],
    [1, 1, 2, 1, 3, 3],
    [1, 1, 2, 3, 3, 1],
    [1, 3, 2, 1, 3, 1],
    [1, 1, 3, 1, 2, 3],
    [1, 1, 3, 3, 2, 1],
    [1, 3, 3, 1, 2, 1],
    [3, 1, 3, 1, 2, 1],
    [2, 1, 1, 3, 3, 1],
    [2, 3, 1, 1, 3, 1],
    [2, 1, 3, 1, 1, 3],
    [2, 1, 3, 3, 1, 1],
    [2, 1, 3, 1, 3, 1],
    [3, 1, 1, 1, 2, 3],
    [3, 1, 1, 3, 2, 1],
    [3, 3, 1, 1, 2, 1],
    [3, 1, 2, 1, 1, 3],
    [3, 1, 2, 3, 1, 1],
    [3, 3, 2, 1, 1, 1],
    [3, 1, 4, 1, 1, 1],
    [2, 2, 1, 4, 1, 1],
    [4, 3, 1, 1, 1, 1],
    [1, 1, 1, 2, 2, 4],
    [1, 1, 1, 4, 2, 2],
    [1, 2, 1, 1, 2, 4],
    [1, 2, 1, 4, 2, 1],
    [1, 4, 1, 1, 2, 2],
    [1, 4, 1, 2, 2, 1],
    [1, 1, 2, 2, 1, 4],
    [1, 1, 2, 4, 1, 2],
    [1, 2, 2, 1, 1, 4],
    [1, 2, 2, 4, 1, 1],
    [1, 4, 2, 1, 1, 2],
    [1, 4, 2, 2, 1, 1],
    [2, 4, 1, 2, 1, 1],
    [2, 2, 1, 1, 1, 4],
    [4, 1, 3, 1, 1, 1],
    [2, 4, 1, 1, 1, 2],
    [1, 3, 4, 1, 1, 1],
    [1, 1, 1, 2, 4, 2],
    [1, 2, 1, 1, 4, 2],
    [1, 2, 1, 2, 4, 1],
    [1, 1, 4, 2, 1, 2],
    [1, 2, 4, 1, 1, 2],
    [1, 2, 4, 2, 1, 1],
    [4, 1, 1, 2, 1, 2],
    [4, 2, 1, 1, 1, 2],
    [4, 2, 1, 2, 1, 1],
    [2, 1, 2, 1, 4, 1],
    [2, 1, 4, 1, 2, 1],
    [4, 1, 2, 1, 2, 1],
    [1, 1, 1, 1, 4, 3],
    [1, 1, 1, 3, 4, 1],
    [1, 3, 1, 1, 4, 1],
    [1, 1, 4, 1, 1, 3],
    [1, 1, 4, 3, 1, 1],
    [4, 1, 1, 1, 1, 3],
    [4, 1, 1, 3, 1, 1],
    [1, 1, 3, 1, 4, 1],
    [1, 1, 4, 1, 3, 1],
    [3, 1, 1, 1, 4, 1],
    [4, 1, 1, 1, 3, 1],
    [2, 1, 1, 4, 1, 2],
    [2, 1, 1, 2, 1, 4],
    [2, 1, 1, 2, 3, 2]
  ];

  /// The stop bars.
  static const List<int> BARS_STOP = [2, 3, 3, 1, 1, 1, 2];

  /// The charset code change.
  static const int CODE_AB_TO_C = 99;

  /// The charset code change.
  static const int CODE_AC_TO_B = 100;

  /// The charset code change.
  static const int CODE_BC_TO_A = 101;

  /// The code for UCC/EAN-128.
  static const int FNC1_INDEX = 102;

  /// The start code.
  static const int START_A = 103;

  /// The start code.
  static const int START_B = 104;

  /// The start code.
  static const int START_C = 105;

  static const int FNC1 = 0x00ca;
  static const int DEL = 0x00c3;
  static const int FNC3 = 0x00c4;
  static const int FNC2 = 0x00c5;
  static const int SHIFT = 0x00c6;
  static const int CODE_C_CHAR = 0x00c7;
  static const int CODE_A_CHAR = 0x00c8;
  static const int FNC4 = 0x00c8;
  static const int STARTA = 0x00cb;
  static const int STARTB = 0x00cc;
  static const int STARTC = 0x00cd;

  static final Map<int, int?> ais = {};

  Barcode128CodeSet _codeSet = Barcode128CodeSet.AUTO;

  /// Creates new Barcode128.
  ///
  /// To generate the font the [PdfDocument.getDefaultFont] will be implicitly called.
  /// If you want to use this barcode in PDF/A documents, please consider using
  /// [Barcode128.customFont].
  factory CraftBarcode128(CraftPdfDocument document, [CraftPdfFont? font]) {
    final resolvedFont = font ?? document.defaultTypeface();
    if (resolvedFont == null) {
      throw CraftPdfException(
          'Could not create default font for barcode. Please provide a font explicitly.');
    }
    return CraftBarcode128._internal(document, resolvedFont);
  }

  CraftBarcode128._internal(super.document, CraftPdfFont font) {
    x = 0.8;
    this.font = font;
    size = 8;
    baseline = size;
    barHeight = size * 3;
    textAlignment = CraftBarcode1D.ALIGN_CENTER;
    codeType = CODE128;
    _initializeAis();
  }

  static bool _aisInitialized = false;

  static void _initializeAis() {
    if (_aisInitialized) return;
    ais[0] = 20;
    ais[1] = 16;
    ais[2] = 16;
    ais[10] = -1;
    ais[11] = 9;
    ais[12] = 8;
    ais[13] = 8;
    ais[15] = 8;
    ais[17] = 8;
    ais[20] = 4;
    ais[21] = -1;
    ais[22] = -1;
    ais[23] = -1;
    ais[240] = -1;
    ais[241] = -1;
    ais[250] = -1;
    ais[251] = -1;
    ais[252] = -1;
    ais[30] = -1;
    for (int k = 3100; k < 3700; ++k) {
      ais[k] = 10;
    }
    ais[37] = -1;
    for (int k = 3900; k < 3940; ++k) {
      ais[k] = -1;
    }
    ais[400] = -1;
    ais[401] = -1;
    ais[402] = 20;
    ais[403] = -1;
    for (int k = 410; k < 416; ++k) {
      ais[k] = 16;
    }
    ais[420] = -1;
    ais[421] = -1;
    ais[422] = 6;
    ais[423] = -1;
    ais[424] = 6;
    ais[425] = 6;
    ais[426] = 6;
    ais[7001] = 17;
    ais[7002] = -1;
    for (int k = 7030; k < 7040; ++k) {
      ais[k] = -1;
    }
    ais[8001] = 18;
    ais[8002] = -1;
    ais[8003] = -1;
    ais[8004] = -1;
    ais[8005] = 10;
    ais[8006] = 22;
    ais[8007] = -1;
    ais[8008] = -1;
    ais[8018] = 22;
    ais[8020] = -1;
    ais[8100] = 10;
    ais[8101] = 14;
    ais[8102] = 6;
    for (int k = 90; k < 100; ++k) {
      ais[k] = -1;
    }
    _aisInitialized = true;
  }

  /// Sets the code set to use.
  void setCodeSet(Barcode128CodeSet codeSet) {
    _codeSet = codeSet;
  }

  /// Get the code set that is used.
  Barcode128CodeSet getCodeSet() {
    return _codeSet;
  }

  /// Removes the FNC1 codes in the text.
  static String removeFNC1(String code) {
    StringBuffer buf = StringBuffer();
    for (int k = 0; k < code.length; ++k) {
      int c = code.codeUnitAt(k);
      if (c >= 32 && c <= 126) {
        buf.writeCharCode(c);
      }
    }
    return buf.toString();
  }

  /// Formats recognized GS1 application identifiers in parentheses.
  /// Unknown or incomplete suffixes remain readable rather than being dropped.
  static String getHumanReadableUCCEAN(String code) {
    _initializeAis();
    final identifiers = <String, int>{
      for (final entry in ais.entries)
        if (entry.value != null && entry.value != 0)
          entry.key.toString().padLeft(2, '0'): entry.value!,
    };
    final lengths = identifiers.keys.map((key) => key.length).toSet().toList()
      ..sort();
    final result = StringBuffer();
    var position = 0;
    while (position < code.length) {
      if (code.codeUnitAt(position) == FNC1) {
        position++;
        continue;
      }
      String? identifier;
      for (final length in lengths) {
        if (position + length > code.length) continue;
        final candidate = code.substring(position, position + length);
        if (identifiers.containsKey(candidate)) {
          identifier = candidate;
          break;
        }
      }
      if (identifier == null) {
        result.write(removeFNC1(code.substring(position)));
        break;
      }
      position += identifier.length;
      final declared = identifiers[identifier]!;
      final limit =
          declared > 0 ? position + declared - identifier.length : code.length;
      var end = position;
      while (end < code.length && end < limit && code.codeUnitAt(end) != FNC1) {
        end++;
      }
      result.write('($identifier)');
      result.write(removeFNC1(code.substring(position, end)));
      position = end;
      if (declared > 0 && end < limit) {
        // A truncated fixed-length field cannot identify subsequent fields safely.
        result.write(removeFNC1(code.substring(position)));
        break;
      }
    }
    return result.toString();
  }

  static String getRawText(String text, bool ucc,
      [Barcode128CodeSet codeSet = Barcode128CodeSet.AUTO]) {
    String out = "";
    int tLen = text.length;
    if (tLen == 0) {
      out += String.fromCharCode(_getStartSymbol(codeSet));
      if (ucc) {
        out += String.fromCharCode(FNC1_INDEX);
      }
      return out;
    }
    int c;
    for (int k = 0; k < tLen; ++k) {
      c = text.codeUnitAt(k);
      if (c > 127 && c != FNC1) {
        throw CraftPdfException(CraftBarcodesExceptionMessageConstant
            .THERE_ARE_ILLEGAL_CHARACTERS_FOR_BARCODE_128);
      }
    }
    c = text.codeUnitAt(0);
    int currentCode = _getStartSymbol(codeSet);
    int index = 0;
    if ((codeSet == Barcode128CodeSet.AUTO || codeSet == Barcode128CodeSet.C) &&
        _isNextDigits(text, index, 2)) {
      currentCode = START_C;
      out += String.fromCharCode(currentCode);
      if (ucc) {
        out += String.fromCharCode(FNC1_INDEX);
      }
      String out2 = _getPackedRawDigits(text, index, 2);
      index += out2.codeUnitAt(0);
      out += out2.substring(1);
    } else {
      if (c < 32) {
        currentCode = START_A;
        out += String.fromCharCode(currentCode);
        if (ucc) {
          out += String.fromCharCode(FNC1_INDEX);
        }
        out += String.fromCharCode(c + 64);
        ++index;
      } else {
        out += String.fromCharCode(currentCode);
        if (ucc) {
          out += String.fromCharCode(FNC1_INDEX);
        }
        if (c == FNC1) {
          out += String.fromCharCode(FNC1_INDEX);
        } else {
          out += String.fromCharCode(c - 32);
        }
        ++index;
      }
    }
    if (codeSet != Barcode128CodeSet.AUTO &&
        currentCode != _getStartSymbol(codeSet)) {
      throw CraftPdfException(CraftBarcodesExceptionMessageConstant
          .THERE_ARE_ILLEGAL_CHARACTERS_FOR_BARCODE_128);
    }
    while (index < tLen) {
      switch (currentCode) {
        case START_A:
          {
            if (codeSet == Barcode128CodeSet.AUTO &&
                _isNextDigits(text, index, 4)) {
              currentCode = START_C;
              out += String.fromCharCode(CODE_AB_TO_C);
              String out2 = _getPackedRawDigits(text, index, 4);
              index += out2.codeUnitAt(0);
              out += out2.substring(1);
            } else {
              c = text.codeUnitAt(index++);
              if (c == FNC1) {
                out += String.fromCharCode(FNC1_INDEX);
              } else {
                if (c > 95) {
                  currentCode = START_B;
                  out += String.fromCharCode(CODE_AC_TO_B);
                  out += String.fromCharCode(c - 32);
                } else {
                  if (c < 32) {
                    out += String.fromCharCode(c + 64);
                  } else {
                    out += String.fromCharCode(c - 32);
                  }
                }
              }
            }
            break;
          }

        case START_B:
          {
            if (codeSet == Barcode128CodeSet.AUTO &&
                _isNextDigits(text, index, 4)) {
              currentCode = START_C;
              out += String.fromCharCode(CODE_AB_TO_C);
              String out2 = _getPackedRawDigits(text, index, 4);
              index += out2.codeUnitAt(0);
              out += out2.substring(1);
            } else {
              c = text.codeUnitAt(index++);
              if (c == FNC1) {
                out += String.fromCharCode(FNC1_INDEX);
              } else {
                if (c < 32) {
                  currentCode = START_A;
                  out += String.fromCharCode(CODE_BC_TO_A);
                  out += String.fromCharCode(c + 64);
                } else {
                  out += String.fromCharCode(c - 32);
                }
              }
            }
            break;
          }

        case START_C:
          {
            if (_isNextDigits(text, index, 2)) {
              String out2 = _getPackedRawDigits(text, index, 2);
              index += out2.codeUnitAt(0);
              out += out2.substring(1);
            } else {
              c = text.codeUnitAt(index++);
              if (c == FNC1) {
                out += String.fromCharCode(FNC1_INDEX);
              } else {
                if (c < 32) {
                  currentCode = START_A;
                  out += String.fromCharCode(CODE_BC_TO_A);
                  out += String.fromCharCode(c + 64);
                } else {
                  currentCode = START_B;
                  out += String.fromCharCode(CODE_AC_TO_B);
                  out += String.fromCharCode(c - 32);
                }
              }
            }
            break;
          }
      }
      if (codeSet != Barcode128CodeSet.AUTO &&
          currentCode != _getStartSymbol(codeSet)) {
        throw CraftPdfException(CraftBarcodesExceptionMessageConstant
            .THERE_ARE_ILLEGAL_CHARACTERS_FOR_BARCODE_128);
      }
    }
    return out;
  }

  static Uint8List getBarsCode128Raw(String text) {
    int idx = text.indexOf('\uffff');
    if (idx >= 0) {
      text = text.substring(0, idx);
    }
    int chk = text.codeUnitAt(0);
    for (int k = 1; k < text.length; ++k) {
      chk += k * text.codeUnitAt(k);
    }
    chk = chk % 103;
    text += String.fromCharCode(chk);
    List<int> bars = [];
    int k_1;
    for (k_1 = 0; k_1 < text.length; ++k_1) {
      bars.addAll(BARS[text.codeUnitAt(k_1)]);
    }
    bars.addAll(BARS_STOP);
    return Uint8List.fromList(bars);
  }

  (List<double>, String) _visualData() {
    final separator = code.indexOf('\uffff');
    final rawMode = codeType == CODE128_RAW;
    final encoded = rawMode
        ? (separator < 0 ? code : code.substring(0, separator))
        : getRawText(code, codeType == CODE128_UCC, _codeSet);
    final label = rawMode
        ? (separator < 0 ? '' : code.substring(separator + 1))
        : codeType == CODE128_UCC
            ? getHumanReadableUCCEAN(code)
            : removeFNC1(code);
    return (
      getBarsCode128Raw(encoded).map((run) => run * x).toList(),
      altText ?? label
    );
  }

  @override
  CraftRectangle getBarcodeSize() {
    final (runs, label) = _visualData();
    return measureLinearSymbol(this, runs, label);
  }

  @override
  Future<CraftRectangle> placeBarcode(CraftPdfCanvas canvas,
      CraftColor? barColor, CraftColor? textColor) async {
    final (runs, label) = _visualData();
    await drawLinearSymbol(this, canvas, runs, label, barColor, textColor);
    return measureLinearSymbol(this, runs, label);
  }

  @override
  void setCode(String code) {
    if (getCodeType() == CODE128_UCC && code.startsWith("(")) {
      int idx = 0;
      StringBuffer ret = StringBuffer();
      while (idx >= 0) {
        int end = code.indexOf(')', idx);
        if (end < 0) {
          throw ArgumentError("Badly formed ucc string");
        }
        String sai = code.substring(idx + 1, end);
        if (sai.length < 2) {
          throw ArgumentError("AI is too short");
        }
        int ai = int.parse(sai);
        int len = ais[ai] ?? 0;
        if (len == 0) {
          throw ArgumentError("AI not found");
        }
        sai = ai.toString();
        if (sai.length == 1) {
          sai = "0$sai";
        }
        idx = code.indexOf('(', end);
        int next = (idx < 0 ? code.length : idx);
        ret.write(sai);
        ret.write(code.substring(end + 1, next));
        if (len < 0) {
          if (idx >= 0) {
            ret.writeCharCode(FNC1);
          }
        } else {
          if (next - end - 1 + sai.length != len) {
            throw ArgumentError("Invalid AI length");
          }
        }
      }
      super.setCode(ret.toString());
    } else {
      super.setCode(code);
    }
  }

  static int _getStartSymbol(Barcode128CodeSet codeSet) {
    switch (codeSet) {
      case Barcode128CodeSet.A:
        return START_A;
      case Barcode128CodeSet.B:
        return START_B;
      case Barcode128CodeSet.C:
        return START_C;
      default:
        return START_B;
    }
  }

  static bool _isNextDigits(String text, int textIndex, int numDigits) {
    int len = text.length;
    while (textIndex < len && numDigits > 0) {
      if (text.codeUnitAt(textIndex) == FNC1) {
        ++textIndex;
        continue;
      }
      int n = math.min(2, numDigits);
      if (textIndex + n > len) {
        return false;
      }
      while (n-- > 0) {
        int c = text.codeUnitAt(textIndex++);
        if (c < 48 || c > 57) {
          // '0' to '9'
          return false;
        }
        --numDigits;
      }
    }
    return numDigits == 0;
  }

  static String _getPackedRawDigits(String text, int textIndex, int numDigits) {
    StringBuffer out = StringBuffer();
    int start = textIndex;
    while (numDigits > 0) {
      if (text.codeUnitAt(textIndex) == FNC1) {
        out.writeCharCode(FNC1_INDEX);
        ++textIndex;
        continue;
      }
      numDigits -= 2;
      int c1 = text.codeUnitAt(textIndex++) - 48; // '0'
      int c2 = text.codeUnitAt(textIndex++) - 48; // '0'
      out.writeCharCode(c1 * 10 + c2);
    }
    String result = out.toString();
    return String.fromCharCode(textIndex - start) + result;
  }
}

enum Barcode128CodeSet { A, B, C, AUTO }
