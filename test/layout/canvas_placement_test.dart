import 'dart:io';
import 'package:test/test.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_writer.dart';
import 'package:pdfcraft/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:pdfcraft/src/kernel/geom/rectangle.dart';
import 'package:pdfcraft/src/layout/canvas.dart';
import 'package:pdfcraft/src/layout/renderer/canvas_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/abstract_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/draw_context.dart';
import 'package:pdfcraft/src/layout/layout/layout_context.dart';
import 'package:pdfcraft/src/layout/layout/layout_result.dart';

class _Probe extends CraftAbstractRenderer {
  int layouts = 0;
  int draws = 0;
  double? available;
  final int status;
  _Probe([this.status = CraftLayoutResult.FULL]) : super(null);
  @override
  CraftLayoutResult layout(CraftLayoutContext context) {
    layouts++;
    available = context.getArea().getBBox().getHeight();
    occupiedArea = context.getArea().clone();
    occupiedArea!.getBBox().setHeight(10);
    return CraftLayoutResult(status, occupiedArea, null, null);
  }

  @override
  Future<void> draw(CraftDrawContext context) async {
    draws++;
  }
}

void main() {
  late Directory temporary;
  late CraftPdfDocument document;
  late CraftCanvas canvas;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('canvas-placement-');
    document = await CraftPdfDocument.create(
        CraftPdfWriter(File('${temporary.path}/result.pdf').openWrite()));
    final page = await document.appendBlankPage();
    canvas = CraftCanvas(
        await CraftPdfCanvas.fromPage(page), CraftRectangle(0, 0, 100, 100));
  });
  tearDown(() async {
    await document.close();
    await temporary.delete(recursive: true);
  });
  for (final immediate in [true, false]) {
    test('child is laid out and drawn once; immediate=$immediate', () async {
      final root = CraftCanvasRenderer(canvas, immediate);
      final first = _Probe();
      final second = _Probe();
      await root.addChild(first);
      await root.addChild(second);
      expect(first.layouts, 1);
      expect(second.layouts, 1);
      expect(first.available, 100);
      expect(second.available, 90);
      expect(first.draws, immediate ? 1 : 0);
      expect(root.getChildRenderers().length, immediate ? 0 : 2);
      await root.flush();
      await root.close();
      expect(first.draws, 1);
      expect(second.draws, 1);
      expect(canvas.getRootArea()!.getHeight(), 100);
    });
  }
  test('overflow is reported before drawing or queuing', () async {
    final root = CraftCanvasRenderer(canvas);
    final child = _Probe(CraftLayoutResult.PARTIAL);
    await expectLater(root.addChild(child), throwsStateError);
    await root.close();
    expect(child.draws, 0);
    expect(root.getChildRenderers(), isEmpty);
  });
}
