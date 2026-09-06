import 'dart:typed_data';

/// Independent reader for the declarative ToUnicode subset of ISO 32000-1,
/// section 9.10.3. It never executes PostScript or resolves external CMaps.
class PdfUnicodeCMap {
  final List<_CodeSpace> _spaces;
  final Map<String, String> _mapping;
  PdfUnicodeCMap._(this._spaces, this._mapping);

  /// Reads codespacerange, bfchar and bfrange blocks. Unsupported inheritance,
  /// malformed Unicode and unmapped input fail explicitly instead of guessing.
  static PdfUnicodeCMap parse(Uint8List bytes) {
    if (bytes.length > 8 * 1024 * 1024) {
      throw const FormatException('ToUnicode exceeds the 8 MiB limit');
    }
    final tokens = _CMapTokens(String.fromCharCodes(bytes));
    final spaces = <_CodeSpace>[];
    final mapping = <String, String>{};
    var expanded = 0;
    var unicodeBytes = 0;
    void put(List<int> source, List<int> target) {
      unicodeBytes += target.length;
      if (unicodeBytes > 8 * 1024 * 1024) {
        throw const FormatException('Expanded Unicode mappings exceed 8 MiB');
      }
      if (++expanded > 262144) {
        throw const FormatException('Too many ToUnicode mappings');
      }
      if (source.isEmpty || source.length > 4) {
        throw const FormatException('Character codes require 1 to 4 bytes');
      }
      mapping[_key(source)] = _unicode(target);
    }

    String? previous;
    while (tokens.hasNext) {
      final token = tokens.next();
      if (token == 'usecmap' || token == '/UseCMap') {
        throw UnsupportedError('Inherited ToUnicode CMaps are unsupported');
      }
      if (token == 'begincidchar' ||
          token == 'begincidrange' ||
          token == 'beginnotdefchar' ||
          token == 'beginnotdefrange') {
        throw UnsupportedError('CID mappings are not ToUnicode mappings');
      }
      if (token == 'begincodespacerange' ||
          token == 'beginbfchar' ||
          token == 'beginbfrange') {
        final count = int.tryParse(previous ?? '');
        if (count == null || count < 0 || count > 100) {
          throw const FormatException('CMap block count must be 0 to 100');
        }
        for (var i = 0; i < count; i++) {
          final first = tokens.hex();
          if (token == 'beginbfchar') {
            put(first, tokens.hex());
            continue;
          }
          final last = tokens.hex();
          if (first.isEmpty ||
              first.length > 4 ||
              first.length != last.length ||
              _number(first) > _number(last)) {
            throw const FormatException('Invalid character code range');
          }
          if (token == 'begincodespacerange') {
            if (spaces.length >= 1024) {
              throw const FormatException('Too many code spaces');
            }
            for (var j = 0; j < first.length; j++) {
              if (first[j] > last[j]) {
                throw const FormatException('Invalid code space byte bounds');
              }
            }
            spaces.add(_CodeSpace(first, last));
          } else {
            final length = _number(last) - _number(first) + 1;
            if (expanded + length > 262144) {
              throw const FormatException('Too many ToUnicode mappings');
            }
            final destination = tokens.next();
            if (destination == '[') {
              for (var j = 0; j < length; j++) {
                put(_bytes(_number(first) + j, first.length), tokens.hex());
              }
              tokens.expect(']');
            } else {
              final target = _hex(destination);
              if (target.isEmpty || target.last + length - 1 > 255) {
                throw const FormatException('bfrange overflows its final byte');
              }
              for (var j = 0; j < length; j++) {
                final value = List<int>.of(target);
                value[value.length - 1] += j;
                put(_bytes(_number(first) + j, first.length), value);
              }
            }
          }
        }
        tokens.expect(token.replaceFirst('begin', 'end'));
      } else if (token == 'endbfchar' ||
          token == 'endbfrange' ||
          token == 'endcodespacerange') {
        throw const FormatException('Unmatched CMap block terminator');
      }
      previous = token;
    }
    if (spaces.isEmpty) throw const FormatException('Missing code space');
    for (var i = 0; i < spaces.length; i++) {
      for (var j = 0; j < i; j++) {
        if (spaces[i].prefixOverlaps(spaces[j])) {
          throw const FormatException('Overlapping or ambiguous code spaces');
        }
      }
    }
    for (final key in mapping.keys) {
      final code = key.codeUnits;
      if (!spaces.any((space) =>
          space.low.length == code.length && space.matches(code, 0))) {
        throw const FormatException('Mapping outside declared code space');
      }
    }
    return PdfUnicodeCMap._(spaces, mapping);
  }

  String decode(Uint8List bytes) {
    final result = StringBuffer();
    var offset = 0;
    while (offset < bytes.length) {
      _CodeSpace? matched;
      for (final space in _spaces) {
        if (space.matches(bytes, offset)) {
          matched = space;
          break;
        }
      }
      if (matched == null) {
        throw FormatException(
            'Invalid or truncated character code', bytes, offset);
      }
      final end = offset + matched.low.length;
      final value = _mapping[_key(bytes.sublist(offset, end))];
      if (value == null) {
        throw FormatException(
            'Character has no Unicode mapping', bytes, offset);
      }
      result.write(value);
      offset = end;
    }
    return result.toString();
  }
}

String _key(List<int> bytes) => String.fromCharCodes(bytes);
int _number(List<int> bytes) => bytes.fold(0, (value, b) => value * 256 + b);
List<int> _bytes(int value, int length) => List.generate(
    length, (index) => (value ~/ (1 << (8 * (length - index - 1)))) & 255);

String _unicode(List<int> bytes) {
  if (bytes.isEmpty || bytes.length.isOdd || bytes.length > 1024) {
    throw const FormatException('Invalid UTF-16BE mapping length');
  }
  final units = <int>[];
  for (var i = 0; i < bytes.length; i += 2) {
    final unit = bytes[i] * 256 + bytes[i + 1];
    units.add(unit);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (i + 3 >= bytes.length)
        throw const FormatException('Unpaired surrogate');
      final low = bytes[i + 2] * 256 + bytes[i + 3];
      if (low < 0xdc00 || low > 0xdfff)
        throw const FormatException('Unpaired surrogate');
      units.add(low);
      i += 2;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Unpaired surrogate');
    }
  }
  return String.fromCharCodes(units);
}

class _CodeSpace {
  final List<int> low, high;
  _CodeSpace(this.low, this.high);
  bool matches(List<int> bytes, int offset) {
    if (bytes.length - offset < low.length) return false;
    for (var i = 0; i < low.length; i++) {
      if (bytes[offset + i] < low[i] || bytes[offset + i] > high[i])
        return false;
    }
    return true;
  }

  bool prefixOverlaps(_CodeSpace other) {
    final length =
        low.length < other.low.length ? low.length : other.low.length;
    for (var i = 0; i < length; i++) {
      if (high[i] < other.low[i] || other.high[i] < low[i]) return false;
    }
    return true;
  }
}

List<int> _hex(String token) {
  if (!token.startsWith('<') ||
      !token.endsWith('>') ||
      token.startsWith('<<')) {
    throw const FormatException('Expected hexadecimal CMap string');
  }
  var body = token
      .substring(1, token.length - 1)
      .replaceAll(RegExp(r'[\x00\t\n\f\r ]'), '');
  if (!RegExp(r'^[0-9a-fA-F]*$').hasMatch(body)) {
    throw const FormatException('Invalid hexadecimal CMap string');
  }
  if (body.length.isOdd) body += '0';
  return [
    for (var i = 0; i < body.length; i += 2)
      int.parse(body.substring(i, i + 2), radix: 16)
  ];
}

class _CMapTokens {
  final String source;
  int position = 0;
  int tokenCount = 0;
  _CMapTokens(this.source);
  void _skip() {
    while (position < source.length) {
      if ('\x00\t\n\f\r '.contains(source[position])) {
        position++;
      } else if (source[position] == '%') {
        while (position < source.length &&
            source[position] != '\r' &&
            source[position] != '\n') {
          position++;
        }
      } else {
        break;
      }
    }
  }

  bool get hasNext {
    _skip();
    return position < source.length;
  }

  String next() {
    if (!hasNext) throw const FormatException('Truncated CMap');
    if (++tokenCount > 1048576) {
      throw const FormatException('Too many CMap tokens');
    }
    final start = position++;
    final first = source[start];
    if (first == '<' && position < source.length && source[position] != '<') {
      while (position < source.length && source[position] != '>') {
        position++;
      }
      if (position == source.length)
        throw const FormatException('Unterminated hex string');
      position++;
    } else if (first == '(') {
      var depth = 1;
      while (position < source.length && depth > 0) {
        final c = source[position++];
        if (c == '\\') {
          if (position < source.length) position++;
        } else if (c == '(') {
          depth++;
        } else if (c == ')') {
          depth--;
        }
      }
      if (depth != 0)
        throw const FormatException('Unterminated literal string');
    } else if ('<>'.contains(first)) {
      if (position < source.length && source[position] == first) position++;
    } else if (!'[]{}'.contains(first)) {
      while (position < source.length &&
          !'\x00\t\n\f\r <>[]{}()/%'.contains(source[position])) {
        position++;
      }
    }
    return source.substring(start, position);
  }

  List<int> hex() => _hex(next());
  void expect(String value) {
    if (next() != value) throw FormatException('Expected $value');
  }
}
