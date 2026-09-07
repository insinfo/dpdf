import 'package:dpdf/src/html/css/css_values.dart';
import 'package:test/test.dart';

void main() {
  test('parses typed absolute and percentage lengths', () {
    expect(CssValues.lengthValue('12px').resolve(100), 9);
    expect(CssValues.lengthValue('25%').resolve(320), 80);
    expect(CssValues.lengthValue('auto').isAuto, isTrue);
    expect(CssValues.lengthValue('-1pt').isAuto, isTrue);
  });

  test('expands CSS edge shorthand clockwise', () {
    final edges = CssValues.edges('1pt 2pt 3pt');
    expect(edges.top.resolve(100), 1);
    expect(edges.right.resolve(100), 2);
    expect(edges.bottom.resolve(100), 3);
    expect(edges.left.resolve(100), 2);
  });
}
