import 'package:dpdf/src/html/css/css_color.dart';
import 'package:test/test.dart';

void main() {
  test('parses portable CSS colors without regular expressions', () {
    final short = CssColors.parse('#f80')!;
    final rgb = CssColors.parse('rgb(0, 128, 255)')!;
    expect(short.red, 1);
    expect(short.green, closeTo(8 / 15, .00001));
    expect(short.blue, 0);
    expect(rgb.green, closeTo(128 / 255, .00001));
    expect(CssColors.parse('transparent'), isNull);
    expect(CssColors.parse('#not-a-color'), isNull);
  });
}
