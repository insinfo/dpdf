import 'dart:typed_data';
import '../pdf_encodings.dart';
import 'cmap_object.dart';

abstract class AbstractCMap {
  String? cmapName;
  String? registry;
  String? ordering;
  int supplement = 0;

  String? getName() => cmapName;

  void setName(String cmapName) {
    this.cmapName = cmapName;
  }

  String? getOrdering() => ordering;

  void setOrdering(String ordering) {
    this.ordering = ordering;
  }

  String? getRegistry() => registry;

  void setRegistry(String registry) {
    this.registry = registry;
  }

  int getSupplement() => supplement;

  void setSupplement(int supplement) {
    this.supplement = supplement;
  }

  void addChar(String mark, CMapObject code);

  void addCodeSpaceRange(Uint8List low, Uint8List high) {}

  void addRange(String from, String to, CMapObject code) {
    Uint8List a1 = decodeStringToByte(from);
    Uint8List a2 = decodeStringToByte(to);
    if (a1.length != a2.length || a1.isEmpty) {
      throw ArgumentError("Invalid map.");
    }
    Uint8List? sout;
    if (code.isString()) {
      sout = decodeStringToByte(code.toString());
    }
    int start = byteArrayToInt(a1);
    int end = byteArrayToInt(a2);
    for (int k = start; k <= end; ++k) {
      intToByteArray(k, a1);
      String mark = PdfEncodings.convertToString(a1, null);
      if (code.isArray()) {
        List<CMapObject> codes = code.getValue() as List<CMapObject>;
        addChar(mark, codes[k - start]);
      } else {
        if (code.isNumber()) {
          int nn = (code.getValue() as int) + k - start;
          addChar(mark, CMapObject(CMapObject.number, nn));
        } else {
          if (code.isString()) {
            CMapObject s1 =
                CMapObject(CMapObject.hexString, Uint8List.fromList(sout!));
            addChar(mark, s1);
            intToByteArray(byteArrayToInt(sout) + 1, sout);
          }
        }
      }
    }
  }

  static Uint8List decodeStringToByte(String range) {
    Uint8List bytes = Uint8List(range.length);
    for (int i = 0; i < range.length; i++) {
      bytes[i] = range.codeUnitAt(i) & 0xFF;
    }
    return bytes;
  }

  String toUnicodeString(String value, bool isHexWriting) {
    Uint8List bytes = decodeStringToByte(value);
    if (isHexWriting) {
      return PdfEncodings.convertToString(
          bytes, PdfEncodings.UNICODE_BIG_UNMARKED);
    } else {
      if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
        return PdfEncodings.convertToString(bytes, PdfEncodings.UNICODE_BIG);
      } else {
        return PdfEncodings.convertToString(
            bytes, PdfEncodings.PDF_DOC_ENCODING);
      }
    }
  }

  static void intToByteArray(int n, Uint8List b) {
    for (int k = b.length - 1; k >= 0; --k) {
      b[k] = n & 0xFF;
      n = n >> 8;
    }
  }

  static int byteArrayToInt(Uint8List b) {
    int n = 0;
    for (int k = 0; k < b.length; ++k) {
      n = n << 8;
      n |= b[k] & 0xFF;
    }
    return n;
  }
}
