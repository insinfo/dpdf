import 'package:html/parser.dart' show parse;
import 'package:dpdf/src/html/css/html_style_sheet.dart';
import 'package:dpdf/src/html/dom/html_box_builder.dart';
import 'package:dpdf/src/html/layout/html_layout_engine.dart';
import 'package:test/test.dart';

void main() {
  test('preserves nested inline styles inside flex and grid items', () {
    final document = parse('''
      <style>
        .flex { display:flex; } .grid { display:grid; grid-template-columns:repeat(2, 1fr); }
        .large { font-size:20pt; } .italic { font-style:italic; }
      </style>
      <section class="flex"><div>plain <strong>bold</strong></div><div class="grid"><span class="large">large</span><em class="italic">italic</em></div></section>
    ''');
    final boxes = HtmlBoxBuilder(
      HtmlStyleSheet.fromDocument(document),
      12,
    ).build(document.body!.nodes);
    final fragments = HtmlLayoutEngine(400).layout(boxes);

    final byText = {
      for (final fragment in fragments) fragment.text.trim(): fragment
    };
    expect(byText.keys, containsAll(['plain', 'bold', 'large', 'italic']));
    expect(byText['bold']!.style.bold, isTrue);
    expect(byText['large']!.style.fontSize, 20);
    expect(byText['italic']!.style.italic, isTrue);
  });

  test('applies typed width, margin, padding and text alignment', () {
    final document = parse('''
      <style>
        .panel { width: 200pt; margin: 10pt 20pt; padding: 5pt 8pt; text-align: center; }
      </style><div class="panel">one two</div>
    ''');
    final boxes = HtmlBoxBuilder(
      HtmlStyleSheet.fromDocument(document),
      12,
    ).build(document.body!.nodes);
    final fragments = HtmlLayoutEngine(400).layout(boxes);

    final first = fragments.firstWhere((fragment) => fragment.text == 'one');
    // x = margin-left + padding-left + centered content offset.
    expect(first.x, greaterThan(100));
    expect(first.baseline, greaterThan(30));
  });

  test('retains text, background and solid border colors in display list', () {
    final document = parse('''
      <style>.paint { color: #f00; background-color: rgb(0, 255, 0); border: 2pt solid blue; }</style>
      <div class="paint">painted</div>
    ''');
    final boxes = HtmlBoxBuilder(
      HtmlStyleSheet.fromDocument(document),
      12,
    ).build(document.body!.nodes);
    final displayList = HtmlLayoutEngine(400).layoutDisplayList(boxes);

    expect(displayList.textFragments.single.style.color.red, 1);
    expect(displayList.boxDecorations, hasLength(1));
    final decoration = displayList.boxDecorations.single;
    expect(decoration.backgroundColor!.green, 1);
    expect(decoration.border!.width, 2);
    expect(decoration.border!.color.blue, 1);
  });
}
