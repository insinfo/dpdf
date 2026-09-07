import 'package:pdfcraft/src/styledxmlparser/css/util/css_variable_util.dart';
import 'package:test/test.dart';

void main() {
  test('resolves chained variables and keeps custom values available', () {
    final styles = <String, String>{
      '--ink': '#123',
      '--theme-color': 'var(--ink)',
      'fill': 'var(--theme-color)',
      'stroke': 'var(--ink)',
    };

    CssVariableUtil.resolveCssVariables(styles);

    expect(styles['--ink'], '#123');
    expect(styles['--theme-color'], '#123');
    expect(styles['fill'], '#123');
    expect(styles['stroke'], '#123');
  });

  test('uses a fallback, including a nested fallback', () {
    final styles = <String, String>{
      '--fallback': 'blue',
      'fill': 'var(--missing, var(--fallback))',
      'stroke': 'var(--missing, rgb(1, 2, 3))',
    };

    CssVariableUtil.resolveCssVariables(styles);

    expect(styles['fill'], 'blue');
    expect(styles['stroke'], 'rgb(1, 2, 3)');
  });

  test('removes declarations whose variable is missing or cyclic', () {
    final styles = <String, String>{
      '--first': 'var(--second)',
      '--second': 'var(--first)',
      'fill': 'var(--first)',
      'stroke': 'var(--missing)',
      'color': 'black',
    };

    CssVariableUtil.resolveCssVariables(styles);

    expect(styles.containsKey('--first'), isFalse);
    expect(styles.containsKey('--second'), isFalse);
    expect(styles.containsKey('fill'), isFalse);
    expect(styles.containsKey('stroke'), isFalse);
    expect(styles['color'], 'black');
  });
}
