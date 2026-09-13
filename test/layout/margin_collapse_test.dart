import 'package:test/test.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/borders/border.dart';
import 'package:dpdf/src/layout/element/div.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/margincollapse/margins_collapse_handler.dart';
import 'package:dpdf/src/layout/margincollapse/margins_collapse_info.dart';
import 'package:dpdf/src/layout/properties/overflow_property_value.dart';
import 'package:dpdf/src/layout/properties/property.dart';

double _layoutHeight(Div root) {
  final renderer = root.createRendererSubTree()!;
  final result = renderer
      .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 2000))));
  expect(result, isNotNull);
  expect(result!.getStatus(), LayoutResult.FULL);
  return result.getOccupiedArea()!.getBBox().getHeight();
}

Div _block(double height) => Div()..setMinHeight(height);

void main() {
  group('MarginsCollapse arithmetic (CSS 2.1, 8.3.1)', () {
    test('collapsed size is the largest positive margin', () {
      final collapse = MarginsCollapse()
        ..joinMargin(10)
        ..joinMargin(30)
        ..joinMargin(20);
      expect(collapse.getCollapsedMarginsSize(), 30);
    });

    test('negative margins are added to the largest positive one', () {
      final collapse = MarginsCollapse()
        ..joinMargin(30)
        ..joinMargin(-10)
        ..joinMargin(-25);
      expect(collapse.getCollapsedMarginsSize(), 30 - 25);
    });

    test('only negative margins collapse to the smallest one', () {
      final collapse = MarginsCollapse()
        ..joinMargin(-5)
        ..joinMargin(-12);
      expect(collapse.getCollapsedMarginsSize(), -12);
    });

    test('an empty set collapses to zero', () {
      final collapse = MarginsCollapse();
      expect(collapse.isEmpty(), isTrue);
      expect(collapse.getCollapsedMarginsSize(), 0);
    });

    test('info keeps the ignore flags handed down to a child', () {
      final info =
          MarginsCollapseInfo(ignoreOwnMarginTop: true, ignoreOwnMarginBottom: false);
      expect(info.isIgnoreOwnMarginTop(), isTrue);
      expect(info.isIgnoreOwnMarginBottom(), isFalse);
      final clone = info.clone();
      clone.ignoreOwnMarginBottom = true;
      expect(info.isIgnoreOwnMarginBottom(), isFalse);
      expect(clone.isIgnoreOwnMarginBottom(), isTrue);
    });
  });

  group('Margin collapsing in block layout', () {
    test('is disabled unless COLLAPSING_MARGINS is requested', () {
      final root = Div()
        ..add(_block(50)..setMarginBottom(20))
        ..add(_block(50)..setMarginTop(30));
      expect(_layoutHeight(root), 150);
    });

    test('adjoining sibling margins collapse to the largest one', () {
      final root = Div()
        ..setProperty(Property.COLLAPSING_MARGINS, true)
        ..add(_block(50)..setMarginBottom(20))
        ..add(_block(50)..setMarginTop(30));
      expect(_layoutHeight(root), 130);
    });

    test('a negative sibling margin is added to the positive one', () {
      final root = Div()
        ..setProperty(Property.COLLAPSING_MARGINS, true)
        ..add(_block(50)..setMarginBottom(-10))
        ..add(_block(50)..setMarginTop(30));
      expect(_layoutHeight(root), 120);
    });

    test('the parent top margin collapses with the first child one', () {
      final root = Div()
        ..setProperty(Property.COLLAPSING_MARGINS, true)
        ..setMarginTop(40)
        ..add(_block(50)..setMarginTop(25));
      expect(_layoutHeight(root), 90);
    });

    test('the parent bottom margin collapses with the last child one', () {
      final root = Div()
        ..setProperty(Property.COLLAPSING_MARGINS, true)
        ..setMarginBottom(40)
        ..add(_block(50)..setMarginBottom(25));
      expect(_layoutHeight(root), 90);
    });

    test('top padding on the parent prevents the collapse', () {
      final root = Div()
        ..setProperty(Property.COLLAPSING_MARGINS, true)
        ..setMarginTop(40)
        ..setPaddingTop(10)
        ..add(_block(50)..setMarginTop(25));
      expect(_layoutHeight(root), 125);
    });

    test('a top border on the parent prevents the collapse', () {
      final root = Div()
        ..setProperty(Property.COLLAPSING_MARGINS, true)
        ..setMarginTop(40)
        ..setProperty(Property.BORDER_TOP, SolidBorder(2))
        ..add(_block(50)..setMarginTop(25));
      expect(_layoutHeight(root), 40 + 2 + 25 + 50);
    });

    test('bottom padding on the parent prevents the bottom collapse', () {
      final root = Div()
        ..setProperty(Property.COLLAPSING_MARGINS, true)
        ..setMarginBottom(40)
        ..setPaddingBottom(10)
        ..add(_block(50)..setMarginBottom(25));
      expect(_layoutHeight(root), 25 + 50 + 10 + 40);
    });

    test('an empty block collapses through its neighbours', () {
      final root = Div()
        ..setProperty(Property.COLLAPSING_MARGINS, true)
        ..add(_block(50)..setMarginBottom(20))
        ..add(Div()
          ..setMarginTop(15)
          ..setMarginBottom(25))
        ..add(_block(50)..setMarginTop(10));
      // Adjoining set {20, 15, 25, 10} collapses to 25.
      expect(_layoutHeight(root), 125);
    });

    test('overflow hidden establishes a new formatting context', () {
      final root = Div()
        ..setProperty(Property.COLLAPSING_MARGINS, true)
        ..setProperty(Property.OVERFLOW_Y, OverflowPropertyValue.hidden)
        ..setMarginTop(40)
        ..add(_block(50)..setMarginTop(25));
      expect(_layoutHeight(root), 115);
    });

    test('a fixed positioned child keeps its own margins out of the flow', () {
      final floating = _block(50)
        ..setMarginTop(30)
        ..setFixedPosition(1, 10, 10, 80);
      final root = Div()
        ..setProperty(Property.COLLAPSING_MARGINS, true)
        ..add(_block(50)..setMarginBottom(20))
        ..add(floating)
        ..add(_block(50)..setMarginTop(10));
      // The out of flow box does not interrupt the adjoining set {20, 10}.
      expect(_layoutHeight(root), 120);
    });
  });

  group('MarginsCollapseHandler blockers', () {
    test('height on the parent stops the bottom collapse', () {
      final root = Div()..setMinHeight(10);
      final renderer = root.createRendererSubTree()!;
      expect(
          MarginsCollapseHandler.blocksBottomMarginCollapseWithChildren(
              renderer, 100),
          isTrue);
    });

    test('a plain div collapses on both edges', () {
      final renderer = Div().createRendererSubTree()!;
      expect(
          MarginsCollapseHandler.blocksTopMarginCollapseWithChildren(
              renderer, 100),
          isFalse);
      expect(
          MarginsCollapseHandler.blocksBottomMarginCollapseWithChildren(
              renderer, 100),
          isFalse);
    });
  });
}
