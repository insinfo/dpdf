import 'package:html/parser.dart' show parse;
import 'package:dpdf/src/html/css/html_style_sheet.dart';
import 'package:dpdf/src/html/dom/html_box_builder.dart';
import 'package:dpdf/src/html/model/html_box.dart';
import 'package:dpdf/src/html/paint/html_standard_font.dart';
import 'package:test/test.dart';

CraftHtmlTextStyle _style(String css) {
  final document =
      parse('<style>.sample { $css }</style><span class="sample">x</span>');
  final boxes =
      CraftHtmlBoxBuilder(CraftHtmlStyleSheet.fromDocument(document), 12)
          .build(document.body!.nodes);
  return boxes.single.style.text;
}

void main() {
  test('maps CSS family lists to the matching standard face', () {
    expect(
        CraftHtmlStandardFont.resolve(_style(
            "font-family: 'Times New Roman', serif; font-weight: 700; font-style: oblique;")),
        'Times-BoldItalic');
    expect(
        CraftHtmlStandardFont.resolve(
            _style('font-family: monospace; font-weight: bold;')),
        'Courier-Bold');
    expect(
        CraftHtmlStandardFont.resolve(
            _style('font-family: missing, Arial; font-style: italic;')),
        'Helvetica-Oblique');
  });

  test('falls back to Helvetica for an unknown family', () {
    expect(CraftHtmlStandardFont.resolve(_style('font-family: Papyrus;')),
        'Helvetica');
    expect(CraftHtmlStandardFont.resolve(_style('font-family: serif;')),
        'Times-Roman');
    expect(
        CraftHtmlStandardFont.resolve(
            _style('font-family: Courier; font-style: italic;')),
        'Courier-Oblique');
  });

  test('normal CSS weight and style override inherited semantic emphasis', () {
    final document = parse('''
      <style>.plain { font-family: Courier; font-weight: normal; font-style: normal; }</style>
      <strong><em class="plain">x</em></strong>
    ''');
    final boxes =
        CraftHtmlBoxBuilder(CraftHtmlStyleSheet.fromDocument(document), 12)
            .build(document.body!.nodes);
    final leaf = boxes.single.children.single.children.single.style.text;
    expect(leaf.bold, isFalse);
    expect(leaf.italic, isFalse);
    expect(CraftHtmlStandardFont.resolve(leaf), 'Courier');
  });
}
