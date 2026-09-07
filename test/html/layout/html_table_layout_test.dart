import 'package:html/parser.dart' show parse;
import 'package:dpdf/src/html/css/html_style_sheet.dart';
import 'package:dpdf/src/html/dom/html_box_builder.dart';
import 'package:dpdf/src/html/layout/html_layout_engine.dart';
import 'package:test/test.dart';

void main() {
  test('table retains header cells and assigns cells to physical columns', () {
    final document = parse('''
      <table><thead><tr><th>HeaderA</th><th>HeaderB</th></tr></thead>
      <tbody><tr><td>CellA</td><td>CellB</td></tr><tr><td>LowerA</td></tr></tbody></table>
    ''');
    final boxes = HtmlBoxBuilder(HtmlStyleSheet.fromDocument(document), 12)
        .build(document.body!.nodes);
    final fragments = HtmlLayoutEngine(300).layout(boxes);
    final byText = {for (final fragment in fragments) fragment.text: fragment};

    expect(byText['HeaderA']!.style.bold, isTrue);
    expect(byText['HeaderB']!.style.bold, isTrue);
    expect(byText['HeaderB']!.x, greaterThan(byText['HeaderA']!.x + 100));
    expect(byText['HeaderB']!.baseline, byText['HeaderA']!.baseline);
    expect(byText['CellA']!.x, byText['HeaderA']!.x);
    expect(byText['CellB']!.x, byText['HeaderB']!.x);
    expect(byText['LowerA']!.baseline, greaterThan(byText['CellA']!.baseline));
  });
}
