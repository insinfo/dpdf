import 'dart:typed_data';
import '../../source/pdf_tokenizer.dart';
import '../../util/pdf_name_util.dart';
import '../pdf_encodings.dart';
import 'cmap_object.dart';

/// Reads CMap operands with the same state machine for both input modes.
class CMapContentParser {
  static const int commandType = 200;
  final PdfTokenizer tokenizer;
  CMapContentParser(this.tokenizer);

  void parse(List<CMapObject> operands) {
    operands.clear();
    while (true) {
      final operand = readObject();
      if (operand == null) return;
      _appendOperand(operands, operand);
      if (operand.isLiteral()) return;
    }
  }

  void parseSync(List<CMapObject> operands) => parse(operands);

  void _appendOperand(List<CMapObject> operands, CMapObject operand) {
    if (operand.isToken()) {
      throw FormatException(
          'CMap closing delimiter has no matching container.');
    }
    operands.add(operand);
  }

  CMapObject readDictionary() => _read(_OperandAssembler(dictionary: true))!;
  CMapObject readDictionarySync() => readDictionary();
  CMapObject readArray() => _read(_OperandAssembler(dictionary: false))!;
  CMapObject readArraySync() => readArray();
  CMapObject? readObject() => _read(_OperandAssembler());
  CMapObject? readObjectSync() => readObject();

  CMapObject? _read(_OperandAssembler state) {
    while (nextValidToken()) {
      final result = state.accept(tokenizer);
      if (result != null) return result;
    }
    return state.finish();
  }

  bool nextValidToken() {
    while (tokenizer.nextToken()) {
      if (tokenizer.getTokenType() != TokenType.comment) return true;
    }
    return false;
  }

  bool nextValidTokenSync() => nextValidToken();

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

class _OperandAssembler {
  final List<_OperandContainer> _containers = [];
  _OperandAssembler({bool? dictionary}) {
    if (dictionary != null) _containers.add(_OperandContainer(dictionary));
  }

  CMapObject? finish() {
    if (_containers.isNotEmpty) {
      throw FormatException('CMap input ended inside a container.');
    }
    return null;
  }

  CMapObject? accept(PdfTokenizer input) {
    final type = input.getTokenType();
    if (type == TokenType.startArray || type == TokenType.startDic) {
      if (_containers.length >= 256) {
        throw FormatException('CMap container nesting exceeds 256 levels.');
      }
      if (_containers.isNotEmpty) _containers.last.checkValuePosition();
      _containers.add(_OperandContainer(type == TokenType.startDic));
      return null;
    }
    CMapObject value;
    if (type == TokenType.endArray || type == TokenType.endDic) {
      final dictionary = type == TokenType.endDic;
      if (_containers.isEmpty) {
        return CMapObject(CMapObject.token, dictionary ? '>>' : ']');
      }
      final frame = _containers.last;
      if (frame.dictionary != dictionary) {
        throw FormatException(
            'CMap container closed with a mismatched delimiter.');
      }
      value = frame.complete();
      _containers.removeLast();
    } else {
      value = _scalar(input);
    }
    if (_containers.isEmpty) return value;
    _containers.last.append(value);
    return null;
  }

  CMapObject _scalar(PdfTokenizer input) {
    switch (input.getTokenType()) {
      case TokenType.name:
        return CMapObject(
            CMapObject.name, PdfNameUtil.decodeName(input.getByteContent()));
      case TokenType.string:
        final hex = input.isHexString();
        return CMapObject(hex ? CMapObject.hexString : CMapObject.string,
            PdfTokenizer.decodeStringContent2(input.getByteContent(), hex));
      case TokenType.number:
        final spelling = input.getStringValue();
        final number = num.tryParse(spelling);
        if (number == null || !number.isFinite) {
          throw FormatException('CMap numeric operand is invalid: $spelling');
        }
        return CMapObject(CMapObject.number,
            number == number.truncateToDouble() ? number.toInt() : number);
      case TokenType.other:
        return CMapObject(CMapObject.literal, input.getStringValue());
      default:
        throw FormatException('CMap contains an unsupported operand token.');
    }
  }
}

class _OperandContainer {
  final bool dictionary;
  final List<CMapObject> items = [];
  final Map<String, CMapObject> entries = {};
  String? _key;
  _OperandContainer(this.dictionary);

  void checkValuePosition() {
    if (dictionary && _key == null) {
      throw FormatException('CMap dictionary requires a name before a value.');
    }
  }

  void append(CMapObject value) {
    if (!dictionary) {
      items.add(value);
    } else if (_key != null) {
      entries[_key!] = value;
      _key = null;
    } else if (value.isName()) {
      _key = value.getValue() as String;
    } else if (!(value.isLiteral() && value.getValue() == 'def')) {
      throw FormatException('CMap dictionary entry must begin with a name.');
    }
  }

  CMapObject complete() {
    if (_key != null) {
      throw FormatException('CMap dictionary has a name without its value.');
    }
    return CMapObject(dictionary ? CMapObject.dictionary : CMapObject.array,
        dictionary ? entries : items);
  }
}
