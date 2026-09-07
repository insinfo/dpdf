import 'package:html/parser.dart' show parse;
import 'package:pdfcraft/src/html/css/css_syntax.dart';
import 'package:pdfcraft/src/html/css/html_style_sheet.dart';
import 'package:test/test.dart';

void main() {
  test('specificity outranks later source order', () {
    final document = parse('''
      <style>#target { display: grid; } div { display: flex; }</style>
      <div id="target"></div>
    ''');
    final styles = CraftHtmlStyleSheet.fromDocument(document);

    expect(
        styles.resolve(document.querySelector('#target')!)['display'], 'grid');
  });

  test('class and tag compound selectors are resolved', () {
    final document = parse(
        '<style>article.card { display: flex; }</style><article class="card"></article>');
    expect(
        CraftHtmlStyleSheet.fromDocument(document)
            .resolve(document.querySelector('article')!)['display'],
        'flex');
  });

  test('keeps delimiters inside strings and CSS functions intact', () {
    final rules = CraftCssSyntax.parseStyleRules('''
      /* one; two */ .card {
        content: "a; b: c";
        background: linear-gradient(90deg, red, blue);
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    ''');
    expect(rules, hasLength(1));
    expect(rules.single.selectorText.trim(), '.card');
    expect(rules.single.declarations.map((item) => item.property),
        ['content', 'background', 'grid-template-columns']);
    expect(rules.single.declarations.first.value, '"a; b: c"');
    expect(rules.single.declarations.last.value, 'repeat(2, minmax(0, 1fr))');
  });

  test('honors important declarations without breaking specificity', () {
    final document = parse('''
      <style>
        #target { display: grid; }
        div { display: flex !important; }
      </style><div id="target" style="display: block"></div>
    ''');
    expect(
        CraftHtmlStyleSheet.fromDocument(document)
            .resolve(document.querySelector('#target')!)['display'],
        'flex');
  });
}
