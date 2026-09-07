import 'package:pdfcraft/src/html/css/css_values.dart';
import 'package:test/test.dart';

void main() {
  test('parses typed absolute and percentage lengths', () {
    expect(CraftCssValues.lengthValue('12px').resolve(100), 9);
    expect(CraftCssValues.lengthValue('25%').resolve(320), 80);
    expect(CraftCssValues.lengthValue('auto').isAuto, isTrue);
    expect(CraftCssValues.lengthValue('-1pt').isAuto, isTrue);
  });

  test('expands CSS edge shorthand clockwise', () {
    final edges = CraftCssValues.edges('1pt 2pt 3pt');
    expect(edges.top.resolve(100), 1);
    expect(edges.right.resolve(100), 2);
    expect(edges.bottom.resolve(100), 3);
    expect(edges.left.resolve(100), 2);
  });
}
