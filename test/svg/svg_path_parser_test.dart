import 'package:dpdf/src/svg/renderers/path/svg_path_parser.dart';
import 'package:test/test.dart';

/// Aproximação usada nas comparações de coordenada: o parser faz aritmética
/// de ponto flutuante (reflexões, elevação de grau, arcos) e comparar por
/// igualdade exata testaria o modo de arredondamento, não a geometria.
const _tolerance = 1e-9;

void _expectCoordinates(CraftSvgPathSegment segment, List<double> expected) {
  expect(segment.coordinates.length, expected.length,
      reason: 'segmento $segment');
  for (var i = 0; i < expected.length; i++) {
    expect(segment.coordinates[i], closeTo(expected[i], _tolerance),
        reason: 'coordenada $i de $segment');
  }
}

void main() {
  group('CraftSvgPathParser', () {
    test('normaliza comandos absolutos em mover, reta e fechar', () {
      final segments = CraftSvgPathParser.parse('M10 20 L30 40 Z');

      expect(segments.map((segment) => segment.op).toList(), [
        CraftSvgPathOp.moveTo,
        CraftSvgPathOp.lineTo,
        CraftSvgPathOp.close,
      ]);
      _expectCoordinates(segments[0], [10, 20]);
      _expectCoordinates(segments[1], [30, 40]);
      expect(segments[2].coordinates, isEmpty);
    });

    test('acumula deslocamentos relativos e repete o comando implícito', () {
      // Depois de um `m`, os pares seguintes valem como `l` relativos.
      final segments = CraftSvgPathParser.parse('m10 10 5 5 5 5');

      expect(segments.map((segment) => segment.op).toList(), [
        CraftSvgPathOp.moveTo,
        CraftSvgPathOp.lineTo,
        CraftSvgPathOp.lineTo,
      ]);
      _expectCoordinates(segments[1], [15, 15]);
      _expectCoordinates(segments[2], [20, 20]);
    });

    test('resolve retas horizontais e verticais mantendo o outro eixo', () {
      final segments = CraftSvgPathParser.parse('M0 0 H10 v5 h-4');

      _expectCoordinates(segments[1], [10, 0]);
      _expectCoordinates(segments[2], [10, 5]);
      _expectCoordinates(segments[3], [6, 5]);
    });

    test('reflete o controle da cúbica anterior em S', () {
      final segments = CraftSvgPathParser.parse('M0 0 C1 1 2 2 3 3 S5 5 6 6');

      // Reflexão de (2,2) em torno do ponto corrente (3,3) dá (4,4).
      _expectCoordinates(segments[2], [4, 4, 5, 5, 6, 6]);
    });

    test('S sem cúbica anterior usa o próprio ponto corrente', () {
      final segments = CraftSvgPathParser.parse('M1 1 S5 5 6 6');

      _expectCoordinates(segments[1], [1, 1, 5, 5, 6, 6]);
    });

    test('eleva a quadrática ao grau três e reflete o controle em T', () {
      final segments = CraftSvgPathParser.parse('M0 0 Q1 1 2 2 T4 4');

      _expectCoordinates(
          segments[1], [2 / 3, 2 / 3, 2 - 2 / 3, 2 - 2 / 3, 2, 2]);
      // Controle refletido: 2*(2,2) - (1,1) = (3,3).
      _expectCoordinates(
          segments[2], [2 + 2 / 3, 2 + 2 / 3, 4 - 2 / 3, 4 - 2 / 3, 4, 4]);
    });

    test('lê os sinalizadores do arco colados ao número seguinte', () {
      // `011 1` são: large-arc 0, sweep 1, destino (1,1).
      final segments = CraftSvgPathParser.parse('M0 0 a5 5 0 011 1');

      expect(segments.first.op, CraftSvgPathOp.moveTo);
      expect(segments.skip(1).every((s) => s.op == CraftSvgPathOp.curveTo),
          isTrue);
      final last = segments.last.coordinates;
      expect(last[4], closeTo(1, 1e-9));
      expect(last[5], closeTo(1, 1e-9));
    });

    test('arco de raio nulo vira reta até o destino', () {
      final segments = CraftSvgPathParser.parse('M0 0 A0 0 0 0 1 10 10');

      expect(segments[1].op, CraftSvgPathOp.lineTo);
      _expectCoordinates(segments[1], [10, 10]);
    });

    test('meia volta produz duas cúbicas terminando no ponto pedido', () {
      final segments = CraftSvgPathParser.parse('M0 0 A5 5 0 0 1 10 0');

      expect(segments.length, 3);
      final end = segments.last.coordinates;
      expect(end[4], closeTo(10, 1e-9));
      expect(end[5], closeTo(0, 1e-9));
      // O topo do semicírculo fica a um raio do eixo; o sentido horário do
      // SVG (Y para baixo) leva o arco para Y negativo.
      expect(segments[1].coordinates[5], lessThan(0));
    });

    test('fechar o subcaminho devolve o ponto corrente ao início dele', () {
      final segments = CraftSvgPathParser.parse('M10 10 L20 20 Z l5 5');

      expect(segments.last.op, CraftSvgPathOp.lineTo);
      _expectCoordinates(segments.last, [15, 15]);
    });

    test('aplica a escala de unidade na emissão', () {
      final segments =
          CraftSvgPathParser.parse('M10 20 L30 40', unitScale: 0.75);

      _expectCoordinates(segments[0], [7.5, 15]);
      _expectCoordinates(segments[1], [22.5, 30]);
    });

    test('preserva o prefixo válido de um caminho truncado', () {
      final segments = CraftSvgPathParser.parse('M10 10 L20');

      expect(segments.length, 1);
      expect(segments.single.op, CraftSvgPathOp.moveTo);
    });

    test('ignora um caminho que começa sem comando', () {
      expect(CraftSvgPathParser.parse('10 10 L20 20'), isEmpty);
      expect(CraftSvgPathParser.parse('   '), isEmpty);
      expect(CraftSvgPathParser.parse(null), isEmpty);
    });

    test('separa números colados por ponto decimal e por sinal', () {
      final segments = CraftSvgPathParser.parse('M1.5.5L-1-2');

      _expectCoordinates(segments[0], [1.5, 0.5]);
      _expectCoordinates(segments[1], [-1, -2]);
    });
  });
}
