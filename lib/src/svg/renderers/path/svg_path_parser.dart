import 'dart:math' as math;

/// Operadores de traçado suportados pelo PDF depois da normalização.
///
/// O `d` do SVG tem vinte formas (absolutas, relativas, taquigrafias, arcos),
/// mas o PDF só conhece quatro. Reduzir tudo a este conjunto no parser mantém
/// os renderizadores triviais e torna o resultado inspecionável em testes.
enum SvgPathOp { moveTo, lineTo, curveTo, close }

/// Um trecho de caminho já em coordenadas absolutas e prontas para o canvas.
class SvgPathSegment {
  final SvgPathOp op;

  /// Pares x/y: vazio em [SvgPathOp.close], dois valores em move/line e
  /// seis (dois controles mais o destino) em curve.
  final List<double> coordinates;

  const SvgPathSegment(this.op, this.coordinates);

  @override
  String toString() => '${op.name}$coordinates';
}

/// Converte o atributo `d` de `<path>` numa lista de segmentos absolutos.
///
/// O iText modela cada operador como uma classe própria; aqui um único
/// autômato resolve o mesmo problema, porque a gramática do caminho é
/// estritamente linear e todo o estado que importa cabe em poucas variáveis
/// (ponto corrente, início do subcaminho e último ponto de controle).
///
/// A varredura por deslocamento e a conversão de arco elíptico em cúbicas
/// seguem de perto `dart_ui/lib/src/graphics/svg/svg_path.dart`, do mesmo
/// autor, adaptadas ao modelo de segmentos usado aqui.
class SvgPathParser {
  SvgPathParser._();

  /// [unitScale] converte unidades de usuário do SVG para pontos do PDF; é
  /// aplicada só na emissão, para o autômato trabalhar sempre no espaço em
  /// que o arquivo foi escrito.
  ///
  /// Um `d` malformado não interrompe a conversão do documento: devolve-se o
  /// prefixo entendido até o erro, que é o comportamento dos agentes de
  /// usuário — um atributo truncado ainda desenha o que dava para desenhar.
  static List<SvgPathSegment> parse(String? pathData,
      {double unitScale = 1.0}) {
    if (pathData == null || pathData.trim().isEmpty) {
      return const <SvgPathSegment>[];
    }
    return _SvgPathScanner(pathData, unitScale).run();
  }
}

/// Sinaliza que o resto do `d` não é interpretável; o prefixo já lido vale.
class _PathTruncated implements Exception {
  const _PathTruncated();
}

class _SvgPathScanner {
  _SvgPathScanner(this._data, this._unitScale);

  static final RegExp _number =
      RegExp(r'[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?');

  final String _data;
  final double _unitScale;
  final List<SvgPathSegment> _segments = [];

  int _offset = 0;
  double _x = 0, _y = 0;
  double _startX = 0, _startY = 0;
  double _cubicX = 0, _cubicY = 0;
  double _quadX = 0, _quadY = 0;
  String? _previous;

  List<SvgPathSegment> run() {
    try {
      _parse();
    } on _PathTruncated {
      // Prefixo válido já está em _segments.
    }
    return _segments;
  }

  void _parse() {
    String? command;
    while (true) {
      _skipSeparators();
      if (_offset >= _data.length) return;
      if (_isCommand(_data.codeUnitAt(_offset))) {
        command = _data[_offset++];
      } else if (command == null || command.toUpperCase() == 'Z') {
        // Números sem comando anterior utilizável não têm interpretação.
        throw const _PathTruncated();
      }
      final current = command;
      final relative = current == current.toLowerCase();
      switch (current.toUpperCase()) {
        case 'M':
          _move(relative);
          // Coordenadas extras depois de um `M` valem como `L`, e é o `L`
          // que passa a valer nas repetições implícitas seguintes.
          final lineCommand = relative ? 'l' : 'L';
          while (_hasNumber) {
            _line(relative);
            _previous = lineCommand;
          }
          command = lineCommand;
          break;
        case 'L':
          _repeat(current, () => _line(relative));
          break;
        case 'H':
          _repeat(current, () {
            _x = _coordinate(_readNumber(), _x, relative);
            _emit(SvgPathOp.lineTo, [_x, _y]);
          });
          break;
        case 'V':
          _repeat(current, () {
            _y = _coordinate(_readNumber(), _y, relative);
            _emit(SvgPathOp.lineTo, [_x, _y]);
          });
          break;
        case 'C':
          _repeat(current, () => _cubic(relative));
          break;
        case 'S':
          _repeat(current, () => _smoothCubic(relative));
          break;
        case 'Q':
          _repeat(current, () => _quadratic(relative));
          break;
        case 'T':
          _repeat(current, () => _smoothQuadratic(relative));
          break;
        case 'A':
          _repeat(current, () => _arc(relative));
          break;
        case 'Z':
          _emit(SvgPathOp.close, const []);
          _x = _startX;
          _y = _startY;
          _previous = current;
          break;
        default:
          throw const _PathTruncated();
      }
    }
  }

  void _emit(SvgPathOp op, List<double> coordinates) {
    _segments.add(SvgPathSegment(
        op, coordinates.map((value) => value * _unitScale).toList()));
  }

  void _move(bool relative) {
    if (!_hasNumber) throw const _PathTruncated();
    _x = _coordinate(_readNumber(), _x, relative);
    _y = _coordinate(_readNumber(), _y, relative);
    _startX = _x;
    _startY = _y;
    _emit(SvgPathOp.moveTo, [_x, _y]);
    _previous = relative ? 'm' : 'M';
  }

  void _line(bool relative) {
    _x = _coordinate(_readNumber(), _x, relative);
    _y = _coordinate(_readNumber(), _y, relative);
    _emit(SvgPathOp.lineTo, [_x, _y]);
  }

  void _cubic(bool relative) {
    final x1 = _coordinate(_readNumber(), _x, relative);
    final y1 = _coordinate(_readNumber(), _y, relative);
    final x2 = _coordinate(_readNumber(), _x, relative);
    final y2 = _coordinate(_readNumber(), _y, relative);
    final x = _coordinate(_readNumber(), _x, relative);
    final y = _coordinate(_readNumber(), _y, relative);
    _emit(SvgPathOp.curveTo, [x1, y1, x2, y2, x, y]);
    _cubicX = x2;
    _cubicY = y2;
    _x = x;
    _y = y;
  }

  void _smoothCubic(bool relative) {
    // Sem uma cúbica imediatamente antes não há o que refletir, e o primeiro
    // controle coincide com o ponto corrente.
    final reflects = _previous == 'C' ||
        _previous == 'c' ||
        _previous == 'S' ||
        _previous == 's';
    final x1 = reflects ? 2 * _x - _cubicX : _x;
    final y1 = reflects ? 2 * _y - _cubicY : _y;
    final x2 = _coordinate(_readNumber(), _x, relative);
    final y2 = _coordinate(_readNumber(), _y, relative);
    final x = _coordinate(_readNumber(), _x, relative);
    final y = _coordinate(_readNumber(), _y, relative);
    _emit(SvgPathOp.curveTo, [x1, y1, x2, y2, x, y]);
    _cubicX = x2;
    _cubicY = y2;
    _x = x;
    _y = y;
  }

  void _quadratic(bool relative) {
    final cx = _coordinate(_readNumber(), _x, relative);
    final cy = _coordinate(_readNumber(), _y, relative);
    final x = _coordinate(_readNumber(), _x, relative);
    final y = _coordinate(_readNumber(), _y, relative);
    _emitQuadratic(cx, cy, x, y);
  }

  void _smoothQuadratic(bool relative) {
    final reflects = _previous == 'Q' ||
        _previous == 'q' ||
        _previous == 'T' ||
        _previous == 't';
    final cx = reflects ? 2 * _x - _quadX : _x;
    final cy = reflects ? 2 * _y - _quadY : _y;
    final x = _coordinate(_readNumber(), _x, relative);
    final y = _coordinate(_readNumber(), _y, relative);
    _emitQuadratic(cx, cy, x, y);
  }

  /// O PDF não tem curva de grau dois: a quadrática é elevada exatamente a
  /// uma cúbica equivalente, sem perda de precisão.
  void _emitQuadratic(double cx, double cy, double x, double y) {
    _emit(SvgPathOp.curveTo, [
      _x + 2 / 3 * (cx - _x),
      _y + 2 / 3 * (cy - _y),
      x + 2 / 3 * (cx - x),
      y + 2 / 3 * (cy - y),
      x,
      y,
    ]);
    _quadX = cx;
    _quadY = cy;
    _x = x;
    _y = y;
  }

  void _arc(bool relative) {
    final rx = _readNumber().abs();
    final ry = _readNumber().abs();
    final rotation = _readNumber();
    // Os sinalizadores são um único dígito e podem vir colados ao número
    // seguinte (`a1 1 0 011 1`), então não passam pelo leitor de números.
    final largeArc = _readFlag();
    final sweep = _readFlag();
    final x = _coordinate(_readNumber(), _x, relative);
    final y = _coordinate(_readNumber(), _y, relative);
    _appendArc(rx, ry, rotation, largeArc, sweep, x, y);
    _x = x;
    _y = y;
  }

  /// Converte o arco elíptico da parametrização por extremos (a do SVG) na
  /// parametrização por centro e aproxima cada quarto de volta por uma
  /// cúbica, conforme o apêndice F.6 da especificação SVG 1.1.
  void _appendArc(double rx, double ry, double degrees, bool largeArc,
      bool sweep, double x1, double y1) {
    final x0 = _x, y0 = _y;
    // Extremos coincidentes anulam o arco; raio nulo degenera em reta. Os dois
    // casos estão previstos na especificação e não são erro.
    if (x0 == x1 && y0 == y1) return;
    if (rx == 0 || ry == 0) {
      _emit(SvgPathOp.lineTo, [x1, y1]);
      return;
    }

    final phi = degrees.remainder(360) * math.pi / 180;
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);
    final dx = (x0 - x1) / 2;
    final dy = (y0 - y1) / 2;
    final xp = cosPhi * dx + sinPhi * dy;
    final yp = -sinPhi * dx + cosPhi * dy;

    // Raios pequenos demais para alcançar o destino são ampliados até caberem,
    // em vez de produzirem uma raiz negativa adiante.
    var actualRx = rx, actualRy = ry;
    final lambda = xp * xp / (rx * rx) + yp * yp / (ry * ry);
    if (lambda > 1) {
      final enlargement = math.sqrt(lambda);
      actualRx *= enlargement;
      actualRy *= enlargement;
    }

    final rx2 = actualRx * actualRx;
    final ry2 = actualRy * actualRy;
    final numerator = math.max(0.0, rx2 * ry2 - rx2 * yp * yp - ry2 * xp * xp);
    final denominator = rx2 * yp * yp + ry2 * xp * xp;
    final sign = largeArc == sweep ? -1.0 : 1.0;
    final factor =
        denominator == 0 ? 0.0 : sign * math.sqrt(numerator / denominator);
    final cxp = factor * actualRx * yp / actualRy;
    final cyp = factor * -actualRy * xp / actualRx;
    final cx = cosPhi * cxp - sinPhi * cyp + (x0 + x1) / 2;
    final cy = sinPhi * cxp + cosPhi * cyp + (y0 + y1) / 2;

    final ux = (xp - cxp) / actualRx;
    final uy = (yp - cyp) / actualRy;
    final vx = (-xp - cxp) / actualRx;
    final vy = (-yp - cyp) / actualRy;
    final start = math.atan2(uy, ux);
    var delta = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
    if (!sweep && delta > 0) delta -= math.pi * 2;
    if (sweep && delta < 0) delta += math.pi * 2;

    // Uma cúbica só aproxima bem até um quarto de volta.
    final count = (delta.abs() / (math.pi / 2)).ceil();
    final step = count == 0 ? 0.0 : delta / count;
    var angle = start;
    for (var i = 0; i < count; i++) {
      final next = angle + step;
      final alpha = 4 / 3 * math.tan(step / 4);
      final cos0 = math.cos(angle), sin0 = math.sin(angle);
      final cos1 = math.cos(next), sin1 = math.sin(next);

      double mapX(double a, double b) =>
          cx + actualRx * cosPhi * a - actualRy * sinPhi * b;
      double mapY(double a, double b) =>
          cy + actualRx * sinPhi * a + actualRy * cosPhi * b;

      final last = i == count - 1;
      _emit(SvgPathOp.curveTo, [
        mapX(cos0 - alpha * sin0, sin0 + alpha * cos0),
        mapY(cos0 - alpha * sin0, sin0 + alpha * cos0),
        mapX(cos1 + alpha * sin1, sin1 - alpha * cos1),
        mapY(cos1 + alpha * sin1, sin1 - alpha * cos1),
        // O último ponto vem do atributo, não da trigonometria: assim o fim
        // do arco coincide exatamente com o início do próximo comando.
        last ? x1 : mapX(cos1, sin1),
        last ? y1 : mapY(cos1, sin1),
      ]);
      angle = next;
    }
  }

  void _repeat(String command, void Function() read) {
    var count = 0;
    while (_hasNumber) {
      read();
      count++;
      _previous = command;
    }
    if (count == 0) throw const _PathTruncated();
  }

  bool get _hasNumber {
    _skipSeparators();
    if (_offset >= _data.length) return false;
    final code = _data.codeUnitAt(_offset);
    return code == 0x2B || code == 0x2D || code == 0x2E || _isDigit(code);
  }

  double _readNumber() {
    _skipSeparators();
    final match = _number.matchAsPrefix(_data, _offset);
    if (match == null) throw const _PathTruncated();
    _offset = match.end;
    final value = double.tryParse(match.group(0)!);
    if (value == null || !value.isFinite) throw const _PathTruncated();
    return value;
  }

  bool _readFlag() {
    _skipSeparators();
    if (_offset >= _data.length) throw const _PathTruncated();
    final code = _data.codeUnitAt(_offset);
    if (code != 0x30 && code != 0x31) throw const _PathTruncated();
    _offset++;
    return code == 0x31;
  }

  void _skipSeparators() {
    while (_offset < _data.length) {
      final code = _data.codeUnitAt(_offset);
      const comma = 0x2C, space = 0x20, tab = 0x09, lf = 0x0A, cr = 0x0D;
      if (code == comma ||
          code == space ||
          code == tab ||
          code == lf ||
          code == cr) {
        _offset++;
      } else {
        break;
      }
    }
  }

  static double _coordinate(double value, double current, bool relative) =>
      relative ? current + value : value;

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

  static bool _isCommand(int code) => switch (code | 0x20) {
        0x6D || 0x7A || 0x6C || 0x68 || 0x76 => true,
        0x63 || 0x73 || 0x71 || 0x74 || 0x61 => true,
        _ => false,
      };
}
