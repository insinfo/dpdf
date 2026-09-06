import 'dart:typed_data';
import 'abstract_cmap.dart';
import 'cmap_object.dart';
import '../pdf_encodings.dart';
import '../../util/int_hashtable.dart';

class CMapToUnicode extends AbstractCMap {
  final Map<int, String> _byteMappings = {};
  final List<Uint8List> _codeSpaceRanges = [];

  CMapToUnicode();

  static CMapToUnicode getIdentity() {
    CMapToUnicode uni = CMapToUnicode();
    for (int i = 0; i < 65537; i++) {
      uni.addCharInt(i, String.fromCharCode(i));
    }
    uni.addCodeSpaceRange(
        Uint8List.fromList([0, 0]), Uint8List.fromList([0xFF, 0xFF]));
    return uni;
  }

  bool hasByteMappings() => _byteMappings.isNotEmpty;

  String? lookup(Uint8List code, [int offset = 0, int? length]) {
    length ??= code.length;
    int key;
    if (length == 1) {
      key = code[offset] & 0xFF;
    } else if (length == 2) {
      key = ((code[offset] & 0xFF) << 8) | (code[offset + 1] & 0xFF);
    } else {
      return null;
    }
    return _byteMappings[key];
  }

  String? lookupInt(int code) => _byteMappings[code];

  Iterable<int> getCodes() => _byteMappings.keys;

  IntHashtable createDirectMapping() {
    IntHashtable result = IntHashtable();
    for (var entry in _byteMappings.entries) {
      if (entry.value.length == 1) {
        result.put(entry.key, entry.value.codeUnitAt(0));
      }
    }
    return result;
  }

  Map<int, int> createReverseMapping() {
    Map<int, int> result = {};
    for (var entry in _byteMappings.entries) {
      if (entry.value.length == 1) {
        result[entry.value.codeUnitAt(0)] = entry.key;
      }
    }
    return result;
  }

  List<Uint8List> getCodeSpaceRanges() => _codeSpaceRanges;

  @override
  void addCodeSpaceRange(Uint8List low, Uint8List high) {
    _codeSpaceRanges.add(low);
    _codeSpaceRanges.add(high);
  }

  void addCharInt(int cid, String uni) {
    _byteMappings[cid] = uni;
  }

  @override
  void addChar(String mark, CMapObject code) {
    int key;
    if (mark.length == 1) {
      key = mark.codeUnitAt(0) & 0xFF;
    } else if (mark.length == 2) {
      key = (mark.codeUnitAt(0) << 8) | mark.codeUnitAt(1);
    } else {
      // PDFium/ warning: more than 2 bytes not supported
      return;
    }

    if (code.isString()) {
      Uint8List bytes;
      if (code.getValue() is Uint8List) {
        bytes = code.getValue() as Uint8List;
      } else {
        bytes = AbstractCMap.decodeStringToByte(code.toString());
      }
      _byteMappings[key] = _createStringFromBytes(bytes);
    } else if (code.isNumber()) {
      _byteMappings[key] = String.fromCharCode(code.getValue() as int);
    }
  }

  String _createStringFromBytes(Uint8List bytes) {
    // If it looks like UTF-16BE (even length and $>1$ bytes)
    if (bytes.length >= 2 && bytes.length % 2 == 0) {
      return PdfEncodings.convertToString(
          bytes, PdfEncodings.UNICODE_BIG_UNMARKED);
    }
    return PdfEncodings.convertToString(bytes, PdfEncodings.PDF_DOC_ENCODING);
  }
}
