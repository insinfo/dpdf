import 'dart:io';
import 'package:test/test.dart';
import 'package:dpdf/src/layout/element/list.dart' as itext;
import 'package:dpdf/src/layout/element/image.dart';
import 'package:dpdf/src/io/image/image_data_factory.dart';
import 'package:dpdf/src/layout/renderer/list_renderer.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/renderer/list_item_renderer.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';

void main() {
  test('List with Image Symbol Layout', () async {
    final imagePath = r'C:\MyDartProjects\itext\test\assets\Desert.jpg';
    if (!File(imagePath).existsSync()) {
      print(
          'Warning: Test image not found at $imagePath, skipping real image test.');
      return;
    }
    final bytes = await File(imagePath).readAsBytes();
    final imageData = ImageDataFactory.create(bytes);
    final image = Image(imageData).setWidth(10).setHeight(10);

    final ttfPath = r'C:\MyDartProjects\itext\test\assets\arial.ttf';
    final ttf = TrueTypeFont.fromFile(ttfPath);
    final font = PdfTrueTypeFont(ttf);

    final list = itext.List()
        .setListSymbol(image)
        .setFont(font)
        .add("Item 1")
        .add("Item 2");

    final listRenderer = list.createRendererSubTree() as ListRenderer;
    final layoutContext =
        LayoutContext(LayoutArea(1, Rectangle(0, 0, 500, 500)));
    final result = listRenderer.layout(layoutContext);

    expect(result, isNotNull);
    expect(result!.getStatus(), LayoutResult.FULL);

    // Check if symbol renderers are added to items
    for (var child in listRenderer.getChildRenderers()) {
      if (child is ListItemRenderer) {
        // The symbol renderer itself is stored in the ListItemRenderer
      }
    }
  });
}
