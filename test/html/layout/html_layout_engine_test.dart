import 'package:pdfcraft/src/html/layout/html_layout_engine.dart';
import 'package:pdfcraft/src/html/layout/html_layout_plan.dart';
import 'package:pdfcraft/src/html/model/html_box.dart';
import 'package:test/test.dart';

CraftHtmlBox _text(String text) => CraftHtmlBox(
      style: const CraftHtmlBoxStyle(
        display: CraftHtmlDisplay.inline,
        text: CraftHtmlTextStyle(12),
      ),
      text: text,
    );

void main() {
  test('flex row assigns distinct physical columns to its children', () {
    final fragments = CraftHtmlLayoutEngine(300).layout([
      CraftHtmlBox(
        style: const CraftHtmlBoxStyle(
          display: CraftHtmlDisplay.flex,
          text: CraftHtmlTextStyle(12),
          gap: 12,
        ),
        children: [_text('esquerda'), _text('direita')],
      ),
    ]);

    expect(fragments.map((fragment) => fragment.text), ['esquerda', 'direita']);
    expect(fragments[0].x, 0);
    expect(fragments[1].x, greaterThan(fragments[0].x));
    expect(fragments[0].baseline, fragments[1].baseline);
  });

  test('grid starts a new row after its configured track count', () {
    final fragments = CraftHtmlLayoutEngine(300).layout([
      CraftHtmlBox(
        style: const CraftHtmlBoxStyle(
          display: CraftHtmlDisplay.grid,
          text: CraftHtmlTextStyle(12),
          gridTemplateColumns: 'repeat(2, 1fr)',
          gap: 10,
        ),
        children: [_text('a'), _text('b'), _text('c')],
      ),
    ]);

    expect(fragments[0].x, 0);
    expect(fragments[1].x, 155);
    expect(fragments[2].x, 0);
    expect(fragments[2].baseline, greaterThan(fragments[0].baseline));
  });

  test('parses nested repeat lists and resolves fixed and fractional tracks',
      () {
    expect(CraftHtmlLayoutPlan.gridColumns('repeat(2, 1fr 2fr) 24pt'), 5);
    expect(CraftHtmlLayoutPlan.gridTrackWidths('100pt 2fr 1fr', 400, gap: 10),
        [100, closeTo(186.6666667, .0001), closeTo(93.3333333, .0001)]);
    expect(CraftHtmlLayoutPlan.gridTrackWidths('120px 1fr', 300), [90, 210]);
  });

  test('grid uses resolved track widths for physical positions', () {
    final fragments = CraftHtmlLayoutEngine(400).layout([
      CraftHtmlBox(
        style: const CraftHtmlBoxStyle(
          display: CraftHtmlDisplay.grid,
          text: CraftHtmlTextStyle(12),
          gridTemplateColumns: '100pt 2fr 1fr',
          gap: 10,
        ),
        children: [_text('first'), _text('second'), _text('third')],
      ),
    ]);

    expect(fragments.map((fragment) => fragment.x), [
      0,
      closeTo(110, .0001),
      closeTo(306.6666667, .0001),
    ]);
    expect(fragments.map((fragment) => fragment.baseline).toSet().length, 1);
  });

  test('flex wrap starts a new line when its intrinsic items no longer fit',
      () {
    final fragments = CraftHtmlLayoutEngine(120).layout([
      CraftHtmlBox(
        style: const CraftHtmlBoxStyle(
          display: CraftHtmlDisplay.flex,
          text: CraftHtmlTextStyle(12),
          flexWrap: true,
          gap: 10,
        ),
        children: [_text('abcdefgh'), _text('ijklmnop'), _text('qrstuvwx')],
      ),
    ]);

    expect(fragments[0].baseline, fragments[1].baseline);
    expect(fragments[2].baseline, greaterThan(fragments[0].baseline));
    expect(fragments[2].x, 0);
  });

  test('justify-content distributes each flex row on the main axis', () {
    CraftHtmlBox flex(CraftHtmlJustifyContent value) => CraftHtmlBox(
          style: CraftHtmlBoxStyle(
            display: CraftHtmlDisplay.flex,
            text: const CraftHtmlTextStyle(12),
            gap: 10,
            justifyContent: value,
            hasJustifyContent: true,
          ),
          children: [_text('aa'), _text('bb')],
        );
    final start = CraftHtmlLayoutEngine(100)
        .layout([flex(CraftHtmlJustifyContent.start)]);
    final center = CraftHtmlLayoutEngine(100)
        .layout([flex(CraftHtmlJustifyContent.center)]);
    final end =
        CraftHtmlLayoutEngine(100).layout([flex(CraftHtmlJustifyContent.end)]);
    final between = CraftHtmlLayoutEngine(100)
        .layout([flex(CraftHtmlJustifyContent.spaceBetween)]);

    expect(start[0].x, 0);
    expect(center[0].x, greaterThan(start[0].x));
    expect(end[0].x, greaterThan(center[0].x));
    expect(between[0].x, 0);
    expect(between[1].x, end[1].x);
    expect(between[1].x - between[0].x, greaterThan(start[1].x - start[0].x));
  });
}
