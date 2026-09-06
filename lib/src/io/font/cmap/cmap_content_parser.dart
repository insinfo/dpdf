import 'dart:typed_data';
import '../../source/pdf_tokenizer.dart';
import '../../util/pdf_name_util.dart';
import '../pdf_encodings.dart';
import 'cmap_object.dart';

class CMapContentParser {
  static const int commandType = 200;

  final PdfTokenizer tokenizer;

  CMapContentParser(this.tokenizer);

  Future<void> parse(List<CMapObject> ls) async {
    ls.clear();
    CMapObject? ob;
    while ((ob = await readObject()) != null) {
      ls.add(ob!);
      if (ob.isLiteral()) {
        break;
      }
    }
  }

  void parseSync(List<CMapObject> ls) {
    ls.clear();
    CMapObject? ob;
    while ((ob = readObjectSync()) != null) {
      ls.add(ob!);
      if (ob.isLiteral()) {
        break;
      }
    }
  }

  Future<CMapObject> readDictionary() async {
    Map<String, CMapObject> dic = {};
    while (true) {
      if (!await nextValidToken()) {
        throw Exception("Unexpected end of file.");
      }
      if (tokenizer.getTokenType() == TokenType.endDic) {
        break;
      }
      if (tokenizer.getTokenType() == TokenType.other &&
          "def" == tokenizer.getStringValue()) {
        continue;
      }
      if (tokenizer.getTokenType() != TokenType.name) {
        throw Exception(
            "Dictionary key ${tokenizer.getStringValue()} is not a name.");
      }
      String name = tokenizer.getStringValue();
      CMapObject? obj = await readObject();
      if (obj == null) {
        throw Exception("Unexpected end of file.");
      }
      if (obj.isToken()) {
        if (obj.toString() == ">>") {
          tokenizer.throwError("Unexpected >>");
        }
        if (obj.toString() == "]") {
          tokenizer.throwError("Unexpected ]");
        }
      }
      dic[name] = obj;
    }
    return CMapObject(CMapObject.dictionary, dic);
  }

  CMapObject readDictionarySync() {
    Map<String, CMapObject> dic = {};
    while (true) {
      if (!nextValidTokenSync()) {
        throw Exception("Unexpected end of file.");
      }
      if (tokenizer.getTokenType() == TokenType.endDic) {
        break;
      }
      if (tokenizer.getTokenType() == TokenType.other &&
          "def" == tokenizer.getStringValue()) {
        continue;
      }
      if (tokenizer.getTokenType() != TokenType.name) {
        throw Exception(
            "Dictionary key ${tokenizer.getStringValue()} is not a name.");
      }
      String name = tokenizer.getStringValue();
      CMapObject? obj = readObjectSync();
      if (obj == null) {
        throw Exception("Unexpected end of file.");
      }
      if (obj.isToken()) {
        if (obj.toString() == ">>") {
          tokenizer.throwError("Unexpected >>");
        }
        if (obj.toString() == "]") {
          tokenizer.throwError("Unexpected ]");
        }
      }
      dic[name] = obj;
    }
    return CMapObject(CMapObject.dictionary, dic);
  }

  Future<CMapObject> readArray() async {
    List<CMapObject> array = [];
    while (true) {
      CMapObject? obj = await readObject();
      if (obj == null) {
        throw Exception("Unexpected end of file.");
      }
      if (obj.isToken()) {
        if (obj.toString() == "]") {
          break;
        }
        if (obj.toString() == ">>") {
          tokenizer.throwError("Unexpected >>");
        }
      }
      array.add(obj);
    }
    return CMapObject(CMapObject.array, array);
  }

  CMapObject readArraySync() {
    List<CMapObject> array = [];
    while (true) {
      CMapObject? obj = readObjectSync();
      if (obj == null) {
        throw Exception("Unexpected end of file.");
      }
      if (obj.isToken()) {
        if (obj.toString() == "]") {
          break;
        }
        if (obj.toString() == ">>") {
          tokenizer.throwError("Unexpected >>");
        }
      }
      array.add(obj);
    }
    return CMapObject(CMapObject.array, array);
  }

  Future<CMapObject?> readObject() async {
    if (!await nextValidToken()) {
      return null;
    }
    TokenType type = tokenizer.getTokenType();
    switch (type) {
      case TokenType.startDic:
        return await readDictionary();
      case TokenType.startArray:
        return await readArray();
      case TokenType.string:
        if (tokenizer.isHexString()) {
          return CMapObject(
              CMapObject.hexString,
              PdfTokenizer.decodeStringContent2(
                  tokenizer.getByteContent(), true));
        } else {
          return CMapObject(
              CMapObject.string,
              PdfTokenizer.decodeStringContent2(
                  tokenizer.getByteContent(), false));
        }
      case TokenType.name:
        return CMapObject(CMapObject.name,
            PdfNameUtil.decodeName(tokenizer.getByteContent()));
      case TokenType.number:
        try {
          return CMapObject(CMapObject.number,
              double.parse(tokenizer.getStringValue()).toInt());
        } catch (e) {
          return CMapObject(CMapObject.number, -2147483648); // int.min
        }
      case TokenType.other:
        return CMapObject(CMapObject.literal, tokenizer.getStringValue());
      case TokenType.endArray:
        return CMapObject(CMapObject.token, "]");
      case TokenType.endDic:
        return CMapObject(CMapObject.token, ">>");
      default:
        return CMapObject(0, "");
    }
  }

  CMapObject? readObjectSync() {
    if (!nextValidTokenSync()) {
      return null;
    }
    TokenType type = tokenizer.getTokenType();
    switch (type) {
      case TokenType.startDic:
        return readDictionarySync();
      case TokenType.startArray:
        return readArraySync();
      case TokenType.string:
        if (tokenizer.isHexString()) {
          return CMapObject(
              CMapObject.hexString,
              PdfTokenizer.decodeStringContent2(
                  tokenizer.getByteContent(), true));
        } else {
          return CMapObject(
              CMapObject.string,
              PdfTokenizer.decodeStringContent2(
                  tokenizer.getByteContent(), false));
        }
      case TokenType.name:
        return CMapObject(CMapObject.name,
            PdfNameUtil.decodeName(tokenizer.getByteContent()));
      case TokenType.number:
        try {
          return CMapObject(CMapObject.number,
              double.parse(tokenizer.getStringValue()).toInt());
        } catch (e) {
          return CMapObject(CMapObject.number, -2147483648); // int.min
        }
      case TokenType.other:
        return CMapObject(CMapObject.literal, tokenizer.getStringValue());
      case TokenType.endArray:
        return CMapObject(CMapObject.token, "]");
      case TokenType.endDic:
        return CMapObject(CMapObject.token, ">>");
      default:
        return CMapObject(0, "");
    }
  }

  Future<bool> nextValidToken() async {
    while (await tokenizer.nextToken()) {
      if (tokenizer.getTokenType() == TokenType.comment) {
        continue;
      }
      return true;
    }
    return false;
  }

  bool nextValidTokenSync() {
    while (tokenizer.nextTokenSync()) {
      if (tokenizer.getTokenType() == TokenType.comment) {
        continue;
      }
      return true;
    }
    return false;
  }

  static String toHex4(int n) {
    return n.toRadixString(16).padLeft(4, '0');
  }

  static String toHex(int n) {
    if (n < 0x10000) {
      return "<${toHex4(n)}>";
    }
    n -= 0x10000;
    int high = (n ~/ 0x400) + 0xD800;
    int low = (n % 0x400) + 0xDC00;
    return "[<${toHex4(high)}${toHex4(low)}>]";
  }

  static String decodeCMapObject(CMapObject cMapObject) {
    if (cMapObject.isHexString()) {
      return PdfEncodings.convertToString(cMapObject.getValue() as Uint8List,
          PdfEncodings.UNICODE_BIG_UNMARKED);
    } else {
      return cMapObject.getValue().toString();
    }
  }
}
