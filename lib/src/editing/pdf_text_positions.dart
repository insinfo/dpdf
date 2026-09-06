part of 'pdf_text_extraction.dart';

/// Width in 1/1000 text units for a single byte character code.
typedef PdfCharacterWidth = double Function(String font, int code);

/// A character's baseline start/end in unrotated PDF page user coordinates.
/// These are advance positions, not the glyph's ink bounding box.
class PdfPositionedCharacter {
  final String text;
  final String font;
  final int code;
  final int textObjectIndex;
  final double x, y, endX, endY;
  const PdfPositionedCharacter(
      this.text, this.font, this.code, this.x, this.y, this.endX, this.endY,
      [this.textObjectIndex = 0]);
}

/// Interprets horizontal, single-byte text state with explicit font metrics.
/// The caller must reject vertical/multibyte fonts before using this API.
class PdfTextPositions {
  static List<PdfPositionedCharacter> fromContent(Uint8List bytes,
      {required PdfCharacterDecoder decoder,
      required PdfCharacterWidth width}) {
    return _TextMachine(decoder, width).read(bytes).characters;
  }
}

class _Affine {
  final double a, b, c, d, e, f;
  const _Affine(
      [this.a = 1, this.b = 0, this.c = 0, this.d = 1, this.e = 0, this.f = 0]);
  _Affine then(_Affine after) => _Affine(
      after.a * a + after.c * b,
      after.b * a + after.d * b,
      after.a * c + after.c * d,
      after.b * c + after.d * d,
      after.a * e + after.c * f + after.e,
      after.b * e + after.d * f + after.f);
  (double, double) at(double x, double y) =>
      (a * x + c * y + e, b * x + d * y + f);
  _Affine shift(double x, double y) => _Affine(1, 0, 0, 1, x, y).then(this);
}

class _TextState {
  String? font;
  double size = 0,
      charSpace = 0,
      wordSpace = 0,
      scale = 1,
      leading = 0,
      rise = 0;
  _Affine ctm = const _Affine();
  _TextState clone() => _TextState()
    ..font = font
    ..size = size
    ..charSpace = charSpace
    ..wordSpace = wordSpace
    ..scale = scale
    ..leading = leading
    ..rise = rise
    ..ctm = ctm;
}

class _TextResult {
  final List<PdfPositionedCharacter> characters;
  final Uint8List content;
  _TextResult(this.characters, this.content);
}

class _TextMachine {
  final PdfCharacterDecoder decoder;
  final PdfCharacterWidth width;
  final Set<String>? allowedFonts;
  _TextMachine(this.decoder, this.width, {this.allowedFonts});
  _TextResult read(Uint8List bytes,
      {Set<int> remove = const {},
      Map<int, Uint8List> insert = const {},
      Map<String, String> fontNames = const {}}) {
    final tokens = _ContentTokens(bytes);
    var state = _TextState();
    final saved = <_TextState>[];
    var text = const _Affine(), line = const _Affine();
    var inText = false;
    var textObjectIndex = 0;
    final characters = <PdfPositionedCharacter>[];
    final operands = <Object>[];
    final output = StringBuffer();
    void requireCount(int count) {
      if (operands.length != count)
        throw FormatException('Invalid content operand count.');
    }

    double number(int i) {
      if (i >= operands.length || operands[i] is! num)
        throw FormatException('Expected numeric operand.');
      final n = (operands[i] as num).toDouble();
      if (!n.isFinite) throw FormatException('Non-finite content operand.');
      return n;
    }

    void advanceLine(double x, double y) {
      line = line.shift(x, y);
      text = line;
    }

    void requireText() {
      if (!inText) throw FormatException('Text operator outside BT/ET.');
    }

    void show(Object item) {
      requireText();
      if (item is! Uint8List ||
          state.font == null ||
          state.size <= 0 ||
          state.scale == 0) {
        throw UnsupportedError(
            'Text requires a font and positive font size/nonzero scale.');
      }
      final pieces = <String>[];
      for (final code in item) {
        final glyphWidth = width(state.font!, code);
        if (!glyphWidth.isFinite || glyphWidth < 0)
          throw FormatException('Invalid character width.');
        final delta = (glyphWidth / 1000 * state.size +
                state.charSpace +
                (code == 32 ? state.wordSpace : 0)) *
            state.scale;
        final matrix = text.then(state.ctm);
        final start = matrix.at(0, state.rise);
        final end = matrix.at(delta, state.rise);
        if (![delta, start.$1, start.$2, end.$1, end.$2]
            .every((v) => v.isFinite)) {
          throw FormatException(
              'Text transformations exceed finite coordinate range.');
        }
        final index = characters.length;
        final replacement = insert[index];
        if (replacement != null && replacement.isNotEmpty) {
          var replacementAdvance = 0.0;
          for (final replacementCode in replacement) {
            final replacementWidth = width(state.font!, replacementCode);
            if (!replacementWidth.isFinite || replacementWidth < 0) {
              throw FormatException('Invalid replacement character width.');
            }
            replacementAdvance += (replacementWidth / 1000 * state.size +
                    state.charSpace +
                    (replacementCode == 32 ? state.wordSpace : 0)) *
                state.scale;
          }
          if (!replacementAdvance.isFinite) {
            throw FormatException('Replacement advance exceeds finite range.');
          }
          pieces.add(
              '<${replacement.map((c) => c.toRadixString(16).padLeft(2, '0')).join()}>');
          // Restore the original text cursor immediately after insertion.
          // The removal advances below then reproduce every original position.
          pieces.add(_pdfNumber(
              replacementAdvance / (state.size * state.scale) * 1000));
        }
        characters.add(PdfPositionedCharacter(
            decoder(state.font!, Uint8List.fromList([code])),
            state.font!,
            code,
            start.$1,
            start.$2,
            end.$1,
            end.$2,
            textObjectIndex));
        if (remove.contains(index)) {
          // TJ values replace the entire advance, including Tc and Tw.
          pieces.add(_pdfNumber(-delta / (state.size * state.scale) * 1000));
        } else {
          pieces.add('<${code.toRadixString(16).padLeft(2, '0')}>');
        }
        text = text.shift(delta, 0);
      }
      output.writeln('[${pieces.join(' ')}] TJ');
    }

    while (true) {
      final token = tokens.next();
      if (token == null) break;
      if (token is! _Operator) {
        operands.add(token);
        continue;
      }
      var emit = true;
      switch (token.value) {
        case 'BT':
          requireCount(0);
          if (inText) throw FormatException('Nested BT.');
          inText = true;
          textObjectIndex++;
          text = const _Affine();
          line = const _Affine();
        case 'ET':
          requireCount(0);
          requireText();
          inText = false;
        case 'q':
          requireCount(0);
          saved.add(state.clone());
        case 'Q':
          requireCount(0);
          if (saved.isEmpty) throw FormatException('Unbalanced Q.');
          state = saved.removeLast();
        case 'cm':
          requireCount(6);
          state.ctm = _Affine(number(0), number(1), number(2), number(3),
                  number(4), number(5))
              .then(state.ctm);
        case 'Tf':
          requireCount(2);
          if (operands[0] is! _Name)
            throw FormatException('Expected font resource name.');
          state.font = (operands[0] as _Name).value;
          state.size = number(1);
          if (allowedFonts != null && !allowedFonts!.contains(state.font)) {
            throw UnsupportedError(
                'Font resource is outside the accepted subset.');
          }
        case 'Tm':
          requireText();
          requireCount(6);
          line = _Affine(
              number(0), number(1), number(2), number(3), number(4), number(5));
          text = line;
        case 'Td':
        case 'TD':
          requireText();
          requireCount(2);
          if (token.value == 'TD') state.leading = -number(1);
          advanceLine(number(0), number(1));
        case 'T*':
          requireText();
          requireCount(0);
          advanceLine(0, -state.leading);
        case 'Tc':
          requireCount(1);
          state.charSpace = number(0);
        case 'Tw':
          requireCount(1);
          state.wordSpace = number(0);
        case 'Tz':
          requireCount(1);
          state.scale = number(0) / 100;
        case 'TL':
          requireCount(1);
          state.leading = number(0);
        case 'Ts':
          requireCount(1);
          state.rise = number(0);
        case 'Tr':
          requireCount(1);
          if (number(0) != 0)
            throw UnsupportedError(
                'Only filled text rendering mode is supported.');
        case 'Tj':
          requireCount(1);
          show(operands[0]);
          emit = false;
        case "'":
          requireText();
          requireCount(1);
          advanceLine(0, -state.leading);
          output.writeln('T*');
          show(operands[0]);
          emit = false;
        case '"':
          requireText();
          requireCount(3);
          state.wordSpace = number(0);
          state.charSpace = number(1);
          advanceLine(0, -state.leading);
          output.writeln(
              '${_pdfNumber(number(0))} Tw ${_pdfNumber(number(1))} Tc T*');
          show(operands[2]);
          emit = false;
        case 'TJ':
          requireText();
          requireCount(1);
          if (operands[0] is! List<Object>)
            throw FormatException('Expected TJ array.');
          for (final item in operands[0] as List<Object>) {
            if (item is num) {
              if (!item.isFinite)
                throw FormatException('Non-finite TJ adjustment.');
              text = text.shift(-item / 1000 * state.size * state.scale, 0);
              output.writeln('[${_pdfNumber(item)}] TJ');
            } else {
              show(item);
            }
          }
          emit = false;
        case 'g':
        case 'G':
          requireCount(1);
          number(0);
        case 'rg':
        case 'RG':
          requireCount(3);
          for (var i = 0; i < 3; i++) {
            number(i);
          }
        case 'k':
        case 'K':
          requireCount(4);
          for (var i = 0; i < 4; i++) {
            number(i);
          }
        default:
          throw UnsupportedError(
              'Positioned text cannot interpret ${token.value}.');
      }
      if (token.value == 'Tf' && fontNames.containsKey(state.font)) {
        operands[0] = _Name(fontNames[state.font]!);
      }
      if (emit)
        output.writeln('${operands.map(_serialize).join(' ')} ${token.value}');
      operands.clear();
    }
    if (inText || saved.isNotEmpty || operands.isNotEmpty)
      throw FormatException('Unbalanced content state.');
    return _TextResult(
        characters, Uint8List.fromList(ascii.encode(output.toString())));
  }

  String _serialize(Object object) {
    if (object is num) return _pdfNumber(object);
    if (object is _Name) {
      final result = StringBuffer('/');
      for (final code in latin1.encode(object.value)) {
        if (code >= 33 &&
            code <= 126 &&
            !const [35, 37, 40, 41, 47, 60, 62, 91, 93, 123, 125]
                .contains(code)) {
          result.writeCharCode(code);
        } else {
          result.write('#${code.toRadixString(16).padLeft(2, '0')}');
        }
      }
      return result.toString();
    }
    throw FormatException('Unexpected retained content operand.');
  }
}

// PDF real numbers use decimal notation; exponent notation is not permitted.
String _pdfNumber(num value) {
  if (!value.isFinite)
    throw FormatException('Non-finite generated PDF number.');
  final text = value.toString();
  final index = text.indexOf('e');
  if (index < 0) return text;
  var mantissa = text.substring(0, index);
  final sign = mantissa.startsWith('-') ? '-' : '';
  if (sign.isNotEmpty) mantissa = mantissa.substring(1);
  final dot = mantissa.indexOf('.');
  final decimal =
      (dot < 0 ? mantissa.length : dot) + int.parse(text.substring(index + 1));
  final digits = mantissa.replaceAll('.', '');
  if (decimal <= 0) return '${sign}0.${'0' * -decimal}$digits';
  if (decimal >= digits.length)
    return '$sign$digits${'0' * (decimal - digits.length)}';
  return '$sign${digits.substring(0, decimal)}.${digits.substring(decimal)}';
}
