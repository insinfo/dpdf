import 'dart:typed_data';
import '../../io/font/cmap/abstract_cmap.dart';
import '../../io/font/cmap/cmap_object.dart';
import '../../io/font/pdf_encodings.dart';
import '../../io/font/cmap/cmap_parser.dart';
import '../../io/font/cmap/cmap_location_from_bytes.dart';
import '../../kernel/pdf/pdf_stream.dart';

class CPDF_ToUnicodeMap extends AbstractCMap {
  final Map<int, int> _map = {};
  final Map<int, String> _multiCharMap = {};

  CPDF_ToUnicodeMap();

  @override
  void addChar(String mark, CMapObject code) {
    int cid =
        AbstractCMap.byteArrayToInt(AbstractCMap.decodeStringToByte(mark));
    if (code.isString()) {
      Uint8List bytes;
      if (code.getValue() is Uint8List) {
        bytes = code.getValue() as Uint8List;
      } else {
        bytes = AbstractCMap.decodeStringToByte(code.toString());
      }

      String unicodeStr;
      if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        unicodeStr =
            PdfEncodings.convertToString(bytes, PdfEncodings.UNICODE_BIG);
      } else if (bytes.length % 2 == 0) {
        unicodeStr = PdfEncodings.convertToString(
            bytes, PdfEncodings.UNICODE_BIG_UNMARKED);
      } else {
        unicodeStr =
            PdfEncodings.convertToString(bytes, PdfEncodings.PDF_DOC_ENCODING);
      }
      _insertIntoMaps(cid, unicodeStr);
    } else if (code.isNumber()) {
      _insertIntoMaps(cid, String.fromCharCode(code.getValue() as int));
    }
  }

  void _insertIntoMaps(int cid, String unicodeStr) {
    if (unicodeStr.length == 1) {
      _map[cid] = unicodeStr.codeUnitAt(0);
    } else if (unicodeStr.isNotEmpty) {
      _multiCharMap[cid] = unicodeStr;
    }
  }

  String lookup(int code) {
    if (_multiCharMap.containsKey(code)) {
      return _multiCharMap[code]!;
    }
    int? unicode = _map[code];
    if (unicode != null) {
      return String.fromCharCode(unicode);
    }
    return '';
  }

  int reverseLookup(int unicode) {
    for (var entry in _map.entries) {
      if (entry.value == unicode) {
        return entry.key;
      }
    }
    return 0;
  }

  int stringToCode(String str) {
    if (str.isEmpty) return 0;
    if (str.length == 1) {
      int code = reverseLookup(str.codeUnitAt(0));
      if (code != 0) return code;
    }
    for (var entry in _multiCharMap.entries) {
      if (entry.value == str) {
        return entry.key;
      }
    }
    return 0;
  }

  String stringToWideString(String str) {
    StringBuffer sb = StringBuffer();
    // Assuming str is a sequence of codes (as bytes).
    // This is how PDFium's StringToWideString treats it for simple cases.
    for (int i = 0; i < str.length; i++) {
      sb.write(lookup(str.codeUnitAt(i)));
    }
    return sb.toString();
  }

  static Future<CPDF_ToUnicodeMap> load(PdfStream stream) async {
    CPDF_ToUnicodeMap cmap = CPDF_ToUnicodeMap();
    Uint8List? bytes = await stream.getBytes();
    if (bytes != null) {
      await CMapParser.parseCid("", cmap, CMapLocationFromBytes(bytes));
    }
    return cmap;
  }

  void handleBeginBFChar(List<CMapObject> list) {
    for (int i = 0; i < list.length - 1; i += 2) {
      String mark = list[i].toString();
      addChar(mark, list[i + 1]);
    }
  }

  void handleBeginBFRange(List<CMapObject> list) {
    for (int i = 0; i < list.length - 2; i += 3) {
      addRange(list[i].toString(), list[i + 1].toString(), list[i + 2]);
    }
  }

  bool getMultiCharIndexIndicator(int code) {
    return _multiCharMap.containsKey(code);
  }

  void setCode(int code, int unicode) {
    _map[code] = unicode;
  }

  void insertIntoMaps(int cid, String unicodeStr) {
    _insertIntoMaps(cid, unicodeStr);
  }
}
