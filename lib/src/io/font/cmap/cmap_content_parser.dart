import 'dart:typed_data';
import '../../source/pdf_tokenizer.dart';
import '../../util/pdf_name_util.dart';
import '../pdf_encodings.dart';
import 'cmap_object.dart';

/// Reads CMap operands with the same state machine for both input modes.
class CraftCMapContentParser {
  static const int commandType = 200;
  final CraftPdfTokenizer tokenizer;
  CraftCMapContentParser(this.tokenizer);

  Future<void> parse(List<CraftCMapObject> operands) async {
    operands.clear();
    while (true) {
      final operand = await readObject();
      if (operand == null) return;
      _appendOperand(operands, operand);
      if (operand.isLiteral()) return;
    }
  }

  void parseSync(List<CraftCMapObject> operands) {
    operands.clear();
    while (true) {
      final operand = readObjectSync();
      if (operand == null) return;
      _appendOperand(operands, operand);
      if (operand.isLiteral()) return;
    }
  }

  void _appendOperand(List<CraftCMapObject> operands, CraftCMapObject operand) {
    if (operand.isToken()) {
      throw FormatException(
          'CMap closing delimiter has no matching container.');
    }
    operands.add(operand);
  }

  Future<CraftCMapObject> readDictionary() async =>
      (await _readAsync(_OperandAssembler(dictionary: true)))!;
  CraftCMapObject readDictionarySync() =>
      _readSync(_OperandAssembler(dictionary: true))!;
  Future<CraftCMapObject> readArray() async =>
      (await _readAsync(_OperandAssembler(dictionary: false)))!;
  CraftCMapObject readArraySync() =>
      _readSync(_OperandAssembler(dictionary: false))!;
  Future<CraftCMapObject?> readObject() => _readAsync(_OperandAssembler());
  CraftCMapObject? readObjectSync() => _readSync(_OperandAssembler());

  Future<CraftCMapObject?> _readAsync(_OperandAssembler state) async {
    while (await nextValidToken()) {
      final result = state.accept(tokenizer);
      if (result != null) return result;
    }
    return state.finish();
  }

  CraftCMapObject? _readSync(_OperandAssembler state) {
    while (nextValidTokenSync()) {
      final result = state.accept(tokenizer);
      if (result != null) return result;
    }
    return state.finish();
  }

  Future<bool> nextValidToken() async {
    while (await tokenizer.nextToken()) {
      if (tokenizer.getTokenType() != TokenType.comment) return true;
    }
    return false;
  }

  bool nextValidTokenSync() {
    while (tokenizer.nextTokenSync()) {
      if (tokenizer.getTokenType() != TokenType.comment) return true;
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

  static String decodeCMapObject(CraftCMapObject cMapObject) {
    if (cMapObject.isHexString()) {
      return CraftPdfEncodings.convertToString(
          cMapObject.getValue() as Uint8List,
          CraftPdfEncodings.UNICODE_BIG_UNMARKED);
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

  CraftCMapObject? finish() {
    if (_containers.isNotEmpty) {
      throw FormatException('CMap input ended inside a container.');
    }
    return null;
  }

  CraftCMapObject? accept(CraftPdfTokenizer input) {
    final type = input.getTokenType();
    if (type == TokenType.startArray || type == TokenType.startDic) {
      if (_containers.length >= 256) {
        throw FormatException('CMap container nesting exceeds 256 levels.');
      }
      if (_containers.isNotEmpty) _containers.last.checkValuePosition();
      _containers.add(_OperandContainer(type == TokenType.startDic));
      return null;
    }
    CraftCMapObject value;
    if (type == TokenType.endArray || type == TokenType.endDic) {
      final dictionary = type == TokenType.endDic;
      if (_containers.isEmpty) {
        return CraftCMapObject(CraftCMapObject.token, dictionary ? '>>' : ']');
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

  CraftCMapObject _scalar(CraftPdfTokenizer input) {
    switch (input.getTokenType()) {
      case TokenType.name:
        return CraftCMapObject(CraftCMapObject.name,
            CraftPdfNameUtil.decodeName(input.getByteContent()));
      case TokenType.string:
        final hex = input.isHexString();
        return CraftCMapObject(
            hex ? CraftCMapObject.hexString : CraftCMapObject.string,
            CraftPdfTokenizer.decodeStringContent2(
                input.getByteContent(), hex));
      case TokenType.number:
        final spelling = input.getStringValue();
        final number = num.tryParse(spelling);
        if (number == null || !number.isFinite) {
          throw FormatException('CMap numeric operand is invalid: $spelling');
        }
        return CraftCMapObject(CraftCMapObject.number,
            number == number.truncateToDouble() ? number.toInt() : number);
      case TokenType.other:
        return CraftCMapObject(CraftCMapObject.literal, input.getStringValue());
      default:
        throw FormatException('CMap contains an unsupported operand token.');
    }
  }
}

class _OperandContainer {
  final bool dictionary;
  final List<CraftCMapObject> items = [];
  final Map<String, CraftCMapObject> entries = {};
  String? _key;
  _OperandContainer(this.dictionary);

  void checkValuePosition() {
    if (dictionary && _key == null) {
      throw FormatException('CMap dictionary requires a name before a value.');
    }
  }

  void append(CraftCMapObject value) {
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

  CraftCMapObject complete() {
    if (_key != null) {
      throw FormatException('CMap dictionary has a name without its value.');
    }
    return CraftCMapObject(
        dictionary ? CraftCMapObject.dictionary : CraftCMapObject.array,
        dictionary ? entries : items);
  }
}
