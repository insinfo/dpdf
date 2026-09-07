import 'dart:typed_data';

import 'package:dgfx/dgfx.dart';
import 'package:html/parser.dart' show parse;

import '../kernel/geom/page_size.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_writer.dart';
import 'css/html_style_sheet.dart';
import 'dom/html_box_builder.dart';
import 'layout/html_layout_engine.dart';
import 'paint/html_pdf_painter.dart';

typedef HtmlFontResourceLoader = Future<Uint8List?> Function(Uri uri);

/// Page and typography settings for [HtmlConverter].
class HtmlConverterProperties {
  final PageSize? pageSize;
  final double margin;
  final double baseFontSize;

  /// Catálogo opcional de fontes incorporáveis.
  ///
  /// Pode conter faces carregadas em memória ou provedores assíncronos para
  /// fontes do sistema, URLs, Google Fonts ou uma integração web com
  /// `FontFace`. Quando nenhuma face CSS é encontrada, o conversor conserva o
  /// fallback para as fontes PDF padrão.
  final BLFontCollection? fontCollection;
  final HtmlFontResourceLoader? fontResourceLoader;

  /// URI usada para resolver URLs relativas declaradas em `@font-face`.
  final Uri? baseUri;

  const HtmlConverterProperties({
    this.pageSize,
    this.margin = 36,
    this.baseFontSize = 12,
    this.fontCollection,
    this.fontResourceLoader,
    this.baseUri,
  })  : assert(margin >= 0),
        assert(baseFontSize > 0);

  PageSize get resolvedPageSize => pageSize ?? PageSize.defaultSize;
}

/// Converts HTML into a new PDF through independent DOM, CSS, layout and
/// paint stages. Markup is parsed only; executable elements are never run.
class HtmlConverter {
  HtmlConverter._();

  static Future<Uint8List> convertToBytes(String html,
      {HtmlConverterProperties? properties}) async {
    final options = properties ?? const HtmlConverterProperties();
    final output = BytesBuilder(copy: false);
    final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
    try {
      await convertInto(html, document, properties: options);
    } finally {
      await document.close();
    }
    return output.takeBytes();
  }

  static Future<void> convertInto(String html, PdfDocument document,
      {HtmlConverterProperties? properties}) async {
    final options = properties ?? const HtmlConverterProperties();
    final parsed = parse(html);
    final body = parsed.body;
    if (body == null) return;

    final styleSheet = HtmlStyleSheet.fromDocument(parsed);
    final fonts = await _loadDeclaredFonts(styleSheet, options);
    final boxes = HtmlBoxBuilder(
      styleSheet,
      options.baseFontSize,
    ).build(body.nodes);
    final pageSize = options.resolvedPageSize;
    final fragments = HtmlLayoutEngine(pageSize.width - options.margin * 2)
        .layoutDisplayList(boxes);
    await HtmlPdfPainter(document, pageSize, options.margin,
            fontCollection: fonts)
        .paint(fragments);
  }

  static Future<BLFontCollection?> _loadDeclaredFonts(
      HtmlStyleSheet sheet, HtmlConverterProperties options) async {
    if (sheet.fontFaces.isEmpty) return options.fontCollection;
    final collection = options.fontCollection ?? BLFontCollection();
    for (final rule in sheet.fontFaces) {
      for (final source in rule.sources) {
        try {
          Uint8List? bytes;
          final uri = Uri.parse(source);
          if (uri.scheme == 'data') {
            bytes = UriData.parse(source).contentAsBytes();
          } else if (options.fontResourceLoader != null) {
            final resolved = options.baseUri?.resolveUri(uri) ?? uri;
            bytes = await options.fontResourceLoader!(resolved);
          }
          if (bytes != null) {
            collection.addBytes(bytes, familyName: rule.family);
            break;
          }
        } on Object {
          // Tenta a próxima origem declarada no mesmo @font-face.
        }
      }
    }
    return collection;
  }
}
