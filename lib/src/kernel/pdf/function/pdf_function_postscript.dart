import 'dart:convert';
import 'dart:math' as math;

import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function.dart';

/// Thrown when a type 4 program is malformed or exceeds an execution guard.
class CraftPdfFunctionPostScriptException implements Exception {
  final String message;

  CraftPdfFunctionPostScriptException(this.message);

  @override
  String toString() => 'CraftPdfFunctionPostScriptException: $message';
}

/// A parsed `{ ... }` procedure of a type 4 function.
///
/// Elements are [double] literals, [String] operator names or nested
/// [CraftPdfPostScriptProcedure]s.
class CraftPdfPostScriptProcedure {
  final List<Object> body;

  CraftPdfPostScriptProcedure(this.body);
}

/// A type 4 (PostScript calculator) function, ISO 32000-1, clause 7.10.5.
class CraftPdfFunctionPostScript extends CraftPdfFunction {
  /// Operand stack limit imposed by clause 7.10.5.
  static const int maxStackSize = 100;

  /// Maximum number of tokens executed by one [evaluate] call.
  ///
  /// The calculator language has no loops, but `if`/`ifelse` nesting and
  /// hand-written or fuzzed programs can still be pathologically large, so a
  /// hard budget keeps a single pixel from stalling a page render.
  static const int maxSteps = 100000;

  /// Maximum `{ }` nesting depth accepted while parsing.
  static const int maxNestingDepth = 100;

  final CraftPdfPostScriptProcedure program;

  final int _outputCount;

  CraftPdfFunctionPostScript(
      super.domain, List<double> super.range, this.program)
      : _outputCount = range.length ~/ 2;

  static Future<CraftPdfFunctionPostScript?> parseStream(
      CraftPdfStream stream, List<double> domain, List<double> range) async {
    final bytes = await stream.getBytes();
    if (bytes == null) return null;
    // The calculator language is ASCII; latin1 never throws on stray bytes.
    final program = parseProgram(latin1.decode(bytes, allowInvalid: true));
    if (program == null) return null;
    return CraftPdfFunctionPostScript(domain, range, program);
  }

  /// Parses the outermost `{ ... }` procedure of a calculator program.
  ///
  /// Returns null when no balanced procedure can be found.
  static CraftPdfPostScriptProcedure? parseProgram(String source) {
    final tokens = _tokenize(source);
    var index = 0;
    while (index < tokens.length && tokens[index] != '{') {
      index++;
    }
    if (index >= tokens.length) return null;
    index++; // consume the opening brace
    try {
      final result = _parseBody(tokens, index, 1);
      return result.procedure;
    } on CraftPdfFunctionPostScriptException {
      return null;
    }
  }

  static List<String> _tokenize(String source) {
    final tokens = <String>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
    }

    var inComment = false;
    for (var i = 0; i < source.length; i++) {
      final ch = source[i];
      if (inComment) {
        if (ch == '\n' || ch == '\r') inComment = false;
        continue;
      }
      if (ch == '%') {
        flush();
        inComment = true;
      } else if (ch == '{' || ch == '}') {
        flush();
        tokens.add(ch);
      } else if (_isWhitespace(ch)) {
        flush();
      } else {
        buffer.write(ch);
      }
    }
    flush();
    return tokens;
  }

  /// The white space characters of ISO 32000-1, table 1.
  static bool _isWhitespace(String ch) {
    final code = ch.codeUnitAt(0);
    return code == 0x00 ||
        code == 0x09 ||
        code == 0x0A ||
        code == 0x0C ||
        code == 0x0D ||
        code == 0x20;
  }

  static _ParseResult _parseBody(List<String> tokens, int index, int depth) {
    if (depth > maxNestingDepth) {
      throw CraftPdfFunctionPostScriptException('procedure nesting too deep');
    }
    final body = <Object>[];
    while (true) {
      if (index >= tokens.length) {
        throw CraftPdfFunctionPostScriptException('unterminated procedure');
      }
      final token = tokens[index++];
      if (token == '}') {
        return _ParseResult(CraftPdfPostScriptProcedure(body), index);
      }
      if (token == '{') {
        final nested = _parseBody(tokens, index, depth + 1);
        body.add(nested.procedure);
        index = nested.nextIndex;
        continue;
      }
      final number = double.tryParse(token);
      if (number != null) {
        body.add(number);
      } else {
        body.add(token.toLowerCase());
      }
    }
  }

  @override
  int get outputCount => _outputCount;

  @override
  List<double> evaluateClipped(List<double> inputs) {
    final stack = <Object>[...inputs];
    final budget = _Budget(maxSteps);
    try {
      _run(program, stack, budget);
    } on CraftPdfFunctionPostScriptException {
      // A broken program yields black rather than aborting a page render.
      return List<double>.filled(_outputCount, 0.0);
    }

    // The n outputs are the topmost n numbers, bottom-to-top (clause 7.10.5).
    final outputs = List<double>.filled(_outputCount, 0.0);
    final start = stack.length - _outputCount;
    for (var j = 0; j < _outputCount; j++) {
      final index = start + j;
      if (index < 0 || index >= stack.length) continue;
      final value = stack[index];
      outputs[j] = value is num ? value.toDouble() : 0.0;
    }
    return outputs;
  }

  static void _run(CraftPdfPostScriptProcedure procedure, List<Object> stack,
      _Budget budget) {
    for (final token in procedure.body) {
      budget.step();
      if (token is double) {
        _push(stack, token);
      } else if (token is CraftPdfPostScriptProcedure) {
        // Procedures are only ever operands of if/ifelse; push them and let
        // those operators consume them.
        _push(stack, token);
      } else {
        _apply(token as String, stack, budget);
      }
    }
  }

  static void _push(List<Object> stack, Object value) {
    if (stack.length >= maxStackSize) {
      throw CraftPdfFunctionPostScriptException('operand stack overflow');
    }
    stack.add(value);
  }

  static Object _pop(List<Object> stack) {
    if (stack.isEmpty) {
      throw CraftPdfFunctionPostScriptException('operand stack underflow');
    }
    return stack.removeLast();
  }

  static double _popNumber(List<Object> stack) {
    final value = _pop(stack);
    if (value is num) return value.toDouble();
    throw CraftPdfFunctionPostScriptException('expected a number');
  }

  static int _popInt(List<Object> stack) {
    final value = _popNumber(stack);
    if (value.isNaN || value.isInfinite) {
      throw CraftPdfFunctionPostScriptException('expected an integer');
    }
    return value.truncate();
  }

  static bool _popBool(List<Object> stack) {
    final value = _pop(stack);
    if (value is bool) return value;
    throw CraftPdfFunctionPostScriptException('expected a boolean');
  }

  static CraftPdfPostScriptProcedure _popProcedure(List<Object> stack) {
    final value = _pop(stack);
    if (value is CraftPdfPostScriptProcedure) return value;
    throw CraftPdfFunctionPostScriptException('expected a procedure');
  }

  static void _apply(String op, List<Object> stack, _Budget budget) {
    switch (op) {
      // --- Arithmetic ---------------------------------------------------
      case 'add':
        final b = _popNumber(stack);
        _push(stack, _popNumber(stack) + b);
      case 'sub':
        final b = _popNumber(stack);
        _push(stack, _popNumber(stack) - b);
      case 'mul':
        final b = _popNumber(stack);
        _push(stack, _popNumber(stack) * b);
      case 'div':
        final b = _popNumber(stack);
        final a = _popNumber(stack);
        _push(stack, b == 0 ? 0.0 : a / b);
      case 'idiv':
        final b = _popInt(stack);
        final a = _popInt(stack);
        _push(stack, b == 0 ? 0.0 : (a ~/ b).toDouble());
      case 'mod':
        final b = _popInt(stack);
        final a = _popInt(stack);
        // PostScript `mod` keeps the sign of the dividend, unlike Dart's `%`.
        _push(stack, b == 0 ? 0.0 : (a - (a ~/ b) * b).toDouble());
      case 'neg':
        _push(stack, -_popNumber(stack));
      case 'abs':
        _push(stack, _popNumber(stack).abs());
      case 'ceiling':
        _push(stack, _popNumber(stack).ceilToDouble());
      case 'floor':
        _push(stack, _popNumber(stack).floorToDouble());
      case 'round':
        _push(stack, _popNumber(stack).roundToDouble());
      case 'truncate':
        _push(stack, _popNumber(stack).truncateToDouble());
      case 'sqrt':
        _push(stack, math.sqrt(math.max(0.0, _popNumber(stack))));
      case 'sin':
        _push(stack, math.sin(_popNumber(stack) * math.pi / 180.0));
      case 'cos':
        _push(stack, math.cos(_popNumber(stack) * math.pi / 180.0));
      case 'atan':
        final den = _popNumber(stack);
        final numerator = _popNumber(stack);
        // PostScript atan answers in degrees in [0, 360).
        var angle = math.atan2(numerator, den) * 180.0 / math.pi;
        if (angle < 0) angle += 360.0;
        _push(stack, angle);
      case 'exp':
        final exponent = _popNumber(stack);
        final base = _popNumber(stack);
        final result = math.pow(base, exponent).toDouble();
        _push(stack, result.isNaN || result.isInfinite ? 0.0 : result);
      case 'ln':
        final value = _popNumber(stack);
        _push(stack, value > 0 ? math.log(value) : 0.0);
      case 'log':
        final value = _popNumber(stack);
        _push(stack, value > 0 ? math.log(value) / math.ln10 : 0.0);
      case 'cvi':
        _push(stack, _popNumber(stack).truncateToDouble());
      case 'cvr':
        _push(stack, _popNumber(stack));

      // --- Relational and boolean ---------------------------------------
      case 'eq':
        final b = _pop(stack);
        _push(stack, _sameValue(_pop(stack), b));
      case 'ne':
        final b = _pop(stack);
        _push(stack, !_sameValue(_pop(stack), b));
      case 'gt':
        final b = _popNumber(stack);
        _push(stack, _popNumber(stack) > b);
      case 'ge':
        final b = _popNumber(stack);
        _push(stack, _popNumber(stack) >= b);
      case 'lt':
        final b = _popNumber(stack);
        _push(stack, _popNumber(stack) < b);
      case 'le':
        final b = _popNumber(stack);
        _push(stack, _popNumber(stack) <= b);
      case 'and':
        _binaryLogical(stack, (a, b) => a && b, (a, b) => a & b);
      case 'or':
        _binaryLogical(stack, (a, b) => a || b, (a, b) => a | b);
      case 'xor':
        _binaryLogical(stack, (a, b) => a != b, (a, b) => a ^ b);
      case 'not':
        final value = _pop(stack);
        if (value is bool) {
          _push(stack, !value);
        } else if (value is num) {
          // On integers `not` is a bitwise complement, not a logical one.
          _push(stack, (~value.truncate()).toDouble());
        } else {
          throw CraftPdfFunctionPostScriptException('not expects bool or int');
        }
      case 'bitshift':
        final shift = _popInt(stack);
        final value = _popInt(stack);
        if (shift.abs() > 63) {
          _push(stack, 0.0);
        } else {
          _push(stack,
              (shift >= 0 ? value << shift : value >> -shift).toDouble());
        }
      case 'true':
        _push(stack, true);
      case 'false':
        _push(stack, false);

      // --- Conditional ---------------------------------------------------
      case 'if':
        final procedure = _popProcedure(stack);
        if (_popBool(stack)) _run(procedure, stack, budget);
      case 'ifelse':
        final elseProcedure = _popProcedure(stack);
        final thenProcedure = _popProcedure(stack);
        _run(_popBool(stack) ? thenProcedure : elseProcedure, stack, budget);

      // --- Stack ----------------------------------------------------------
      case 'pop':
        _pop(stack);
      case 'exch':
        final b = _pop(stack);
        final a = _pop(stack);
        _push(stack, b);
        _push(stack, a);
      case 'dup':
        final a = _pop(stack);
        _push(stack, a);
        _push(stack, a);
      case 'copy':
        final count = _popInt(stack);
        if (count < 0 || count > stack.length) {
          throw CraftPdfFunctionPostScriptException('copy out of range');
        }
        final start = stack.length - count;
        for (var i = 0; i < count; i++) {
          _push(stack, stack[start + i]);
        }
      case 'index':
        final offset = _popInt(stack);
        if (offset < 0 || offset >= stack.length) {
          throw CraftPdfFunctionPostScriptException('index out of range');
        }
        _push(stack, stack[stack.length - 1 - offset]);
      case 'roll':
        final shift = _popInt(stack);
        final count = _popInt(stack);
        if (count < 0 || count > stack.length) {
          throw CraftPdfFunctionPostScriptException('roll out of range');
        }
        if (count > 0 && shift != 0) {
          final start = stack.length - count;
          final window = stack.sublist(start);
          // A positive shift moves elements towards the top of the stack.
          final normalized = ((shift % count) + count) % count;
          for (var i = 0; i < count; i++) {
            stack[start + (i + normalized) % count] = window[i];
          }
        }

      default:
        throw CraftPdfFunctionPostScriptException('unknown operator $op');
    }
  }

  /// `and`, `or` and `xor` are logical on booleans and bitwise on integers.
  static void _binaryLogical(List<Object> stack,
      bool Function(bool, bool) onBool, int Function(int, int) onInt) {
    final b = _pop(stack);
    final a = _pop(stack);
    if (a is bool && b is bool) {
      _push(stack, onBool(a, b));
    } else if (a is num && b is num) {
      _push(stack, onInt(a.truncate(), b.truncate()).toDouble());
    } else {
      throw CraftPdfFunctionPostScriptException('type mismatch');
    }
  }

  static bool _sameValue(Object a, Object b) {
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    if (a is bool && b is bool) return a == b;
    return false;
  }
}

class _ParseResult {
  final CraftPdfPostScriptProcedure procedure;
  final int nextIndex;

  _ParseResult(this.procedure, this.nextIndex);
}

class _Budget {
  int _remaining;

  _Budget(this._remaining);

  void step() {
    if (--_remaining < 0) {
      throw CraftPdfFunctionPostScriptException('execution budget exhausted');
    }
  }
}
