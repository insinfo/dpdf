import 'dart:typed_data';

import 'package:html/parser.dart' show parse;

import '../kernel/geom/page_size.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_writer.dart';
import 'css/html_style_sheet.dart';
import 'dom/html_box_builder.dart';
import 'layout/html_layout_engine.dart';
import 'paint/html_pdf_painter.dart';

/// Page and typography settings for [CraftHtmlConverter].
class CraftHtmlConverterProperties {
  final CraftPageSize? pageSize;
  final double margin;
  final double baseFontSize;

  const CraftHtmlConverterProperties({
    this.pageSize,
    this.margin = 36,
    this.baseFontSize = 12,
  })  : assert(margin >= 0),
        assert(baseFontSize > 0);

  CraftPageSize get resolvedPageSize => pageSize ?? CraftPageSize.defaultSize;
}

/// Converts HTML into a new PDF through independent DOM, CSS, layout and
/// paint stages. Markup is parsed only; executable elements are never run.
class CraftHtmlConverter {
  CraftHtmlConverter._();

  static Future<Uint8List> convertToBytes(String html,
      {CraftHtmlConverterProperties? properties}) async {
    final options = properties ?? const CraftHtmlConverterProperties();
    final output = BytesBuilder(copy: false);
    final document =
        await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(output));
    try {
      await convertInto(html, document, properties: options);
    } finally {
      await document.close();
    }
    return output.takeBytes();
  }

  static Future<void> convertInto(String html, CraftPdfDocument document,
      {CraftHtmlConverterProperties? properties}) async {
    final options = properties ?? const CraftHtmlConverterProperties();
    final parsed = parse(html);
    final body = parsed.body;
    if (body == null) return;

    final boxes = CraftHtmlBoxBuilder(
      CraftHtmlStyleSheet.fromDocument(parsed),
      options.baseFontSize,
    ).build(body.nodes);
    final pageSize = options.resolvedPageSize;
    final fragments = CraftHtmlLayoutEngine(pageSize.width - options.margin * 2)
        .layoutDisplayList(boxes);
    await CraftHtmlPdfPainter(document, pageSize, options.margin)
        .paint(fragments);
  }
}
