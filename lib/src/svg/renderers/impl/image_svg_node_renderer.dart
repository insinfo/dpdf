import 'dart:typed_data';

import 'package:dpdf/src/io/image/image_data_factory.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

class ImageSvgNodeRenderer extends AbstractSvgNodeRenderer {
  @override
  bool canElementFill() => false;

  @override
  Future<void> preDraw(SvgDrawContext context) async {}

  @override
  Future<void> postDraw(SvgDrawContext context) async {}

  @override
  Future<void> doDraw(SvgDrawContext context) async {
    final href = getAttribute(SvgAttributes.HREF) ??
        getAttribute(SvgAttributes.XLINK_HREF);
    if (href == null || href.trim().isEmpty) return;
    final width = parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.WIDTH, '0'), context);
    final height = parseVerticalLength(
        getAttributeOrDefault(SvgAttributes.HEIGHT, '0'), context);
    if (width <= 0 || height <= 0) return;

    Uint8List? bytes;
    try {
      final uri = Uri.parse(href.trim());
      if (uri.scheme == 'data') {
        bytes = UriData.parse(href.trim()).contentAsBytes();
      } else {
        bytes = await context.resourceLoader?.call(uri);
      }
    } on FormatException {
      return;
    }
    if (bytes == null || bytes.isEmpty) return;

    final canvas = context.getCurrentCanvas();
    if (canvas.resources == null || canvas.getDocument() == null) return;
    try {
      final image = ImageDataFactory.create(bytes);
      final x = parseHorizontalLength(
          getAttributeOrDefault(SvgAttributes.X, '0'), context);
      final y = parseVerticalLength(
          getAttributeOrDefault(SvgAttributes.Y, '0'), context);
      await canvas.addImageWithTransformationMatrix(
          image, width, 0, 0, height, x, y);
    } on Object {
      // SVG trata recurso ausente ou ilegível como uma imagem que não pinta.
    }
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => Rectangle(
        parseHorizontalLength(
            getAttributeOrDefault(SvgAttributes.X, '0'), context),
        parseVerticalLength(
            getAttributeOrDefault(SvgAttributes.Y, '0'), context),
        parseHorizontalLength(
            getAttributeOrDefault(SvgAttributes.WIDTH, '0'), context),
        parseVerticalLength(
            getAttributeOrDefault(SvgAttributes.HEIGHT, '0'), context),
      );

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = ImageSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
