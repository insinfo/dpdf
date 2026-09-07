import 'package:dpdf/src/html/layout/html_layout_engine.dart';
import 'package:dpdf/src/html/layout/html_layout_plan.dart';
import 'package:dpdf/src/html/model/html_box.dart';
import 'package:test/test.dart';

HtmlBox _text(String text) => HtmlBox(
      style: const HtmlBoxStyle(
        display: HtmlDisplay.inline,
        text: HtmlTextStyle(12),
      ),
      text: text,
    );

void main() {
  test('flex row assigns distinct physical columns to its children', () {
    final fragments = HtmlLayoutEngine(300).layout([
      HtmlBox(
        style: const HtmlBoxStyle(
          display: HtmlDisplay.flex,
          text: HtmlTextStyle(12),
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
    final fragments = HtmlLayoutEngine(300).layout([
      HtmlBox(
        style: const HtmlBoxStyle(
          display: HtmlDisplay.grid,
          text: HtmlTextStyle(12),
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
    expect(HtmlLayoutPlan.gridColumns('repeat(2, 1fr 2fr) 24pt'), 5);
    expect(HtmlLayoutPlan.gridTrackWidths('100pt 2fr 1fr', 400, gap: 10),
        [100, closeTo(186.6666667, .0001), closeTo(93.3333333, .0001)]);
    expect(HtmlLayoutPlan.gridTrackWidths('120px 1fr', 300), [90, 210]);
  });

  test('grid uses resolved track widths for physical positions', () {
    final fragments = HtmlLayoutEngine(400).layout([
      HtmlBox(
        style: const HtmlBoxStyle(
          display: HtmlDisplay.grid,
          text: HtmlTextStyle(12),
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
    final fragments = HtmlLayoutEngine(120).layout([
      HtmlBox(
        style: const HtmlBoxStyle(
          display: HtmlDisplay.flex,
          text: HtmlTextStyle(12),
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
    HtmlBox flex(HtmlJustifyContent value) => HtmlBox(
          style: HtmlBoxStyle(
            display: HtmlDisplay.flex,
            text: const HtmlTextStyle(12),
            gap: 10,
            justifyContent: value,
            hasJustifyContent: true,
          ),
          children: [_text('aa'), _text('bb')],
        );
    final start =
        HtmlLayoutEngine(100).layout([flex(HtmlJustifyContent.start)]);
    final center =
        HtmlLayoutEngine(100).layout([flex(HtmlJustifyContent.center)]);
    final end = HtmlLayoutEngine(100).layout([flex(HtmlJustifyContent.end)]);
    final between =
        HtmlLayoutEngine(100).layout([flex(HtmlJustifyContent.spaceBetween)]);

    expect(start[0].x, 0);
    expect(center[0].x, greaterThan(start[0].x));
    expect(end[0].x, greaterThan(center[0].x));
    expect(between[0].x, 0);
    expect(between[1].x, end[1].x);
    expect(between[1].x - between[0].x, greaterThan(start[1].x - start[0].x));
  });
}
