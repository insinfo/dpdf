import 'package:dgfx/dgfx.dart';

import '../layout/html_display_list.dart';
import '../layout/html_text_measure.dart';
import '../model/html_box.dart';
import '../css/css_color.dart';
import '../../kernel/colors/device_rgb.dart';
import 'html_standard_font.dart';
import '../../kernel/font/pdf_font_factory.dart';
import '../../kernel/font/pdf_font.dart';
import '../../kernel/font/pdf_type0_font.dart';
import '../../io/font/true_type_font.dart';
import '../../kernel/geom/page_size.dart';
import '../../kernel/geom/rectangle.dart';
import '../../kernel/pdf/canvas/pdf_canvas.dart';
import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/pdf/pdf_page.dart';
import 'html_pdf_link_annotation.dart';
import '../../svg/svg_converter.dart';

/// Paints the platform-neutral HTML display list into paginated PDF pages.
class HtmlPdfPainter {
  final PdfDocument document;
  final PageSize pageSize;
  final double margin;
  final BLFontCollection? fontCollection;
  final Map<BLFontFace, PdfFont> _embeddedFonts = <BLFontFace, PdfFont>{};

  HtmlPdfPainter(this.document, this.pageSize, this.margin,
      {this.fontCollection});

  Future<void> paint(HtmlDisplayList displayList) async {
    final usableHeight = pageSize.height - margin * 2;
    final canvases = <PdfCanvas>[];
    final pages = <PdfPage>[];
    Future<PdfCanvas> canvasAt(int pageIndex) async {
      while (canvases.length <= pageIndex) {
        final page = await document.appendBlankPage(pageSize);
        pages.add(page);
        canvases.add(await PdfCanvas.fromPage(page));
      }
      return canvases[pageIndex];
    }

    // Decorations are emitted before glyphs, preserving CSS paint order.
    for (final decoration in displayList.boxDecorations) {
      var top = decoration.top;
      final bottom = decoration.top + decoration.height;
      while (top < bottom) {
        final pageIndex = (top / usableHeight).floor();
        final localTop = top - pageIndex * usableHeight;
        final segmentHeight =
            (bottom - top).clamp(0.0, usableHeight - localTop);
        final canvas = await canvasAt(pageIndex);
        canvas.saveState();
        if (decoration.backgroundColor case final background?) {
          canvas.setFillColor(_pdfColor(background));
        }
        if (decoration.border case final border?) {
          canvas
            ..setStrokeColor(_pdfColor(border.color))
            ..setLineWidth(border.width);
        }
        canvas.rectangle(
            margin + decoration.x,
            pageSize.height - margin - localTop - segmentHeight,
            decoration.width,
            segmentHeight);
        if (decoration.backgroundColor != null &&
            decoration.border?.visible == true) {
          canvas.fillStroke();
        } else if (decoration.backgroundColor != null) {
          canvas.fill();
        } else if (decoration.border?.visible == true) {
          canvas.stroke();
        }
        canvas.restoreState();
        top += segmentHeight;
      }
    }
    for (final fragment in displayList.imageFragments) {
      final pageIndex = (fragment.top / usableHeight).floor();
      final canvas = await canvasAt(pageIndex);
      final localTop = fragment.top - pageIndex * usableHeight;
      await canvas.addImageWithTransformationMatrix(
          fragment.image.image,
          fragment.width,
          0,
          0,
          fragment.height,
          margin + fragment.x,
          pageSize.height - margin - localTop - fragment.height);
    }
    for (final fragment in displayList.svgFragments) {
      final pageIndex = (fragment.top / usableHeight).floor();
      await canvasAt(pageIndex);
      final localTop = fragment.top - pageIndex * usableHeight;
      await SvgConverter.drawOnPage(fragment.image.source, pages[pageIndex],
          viewport: Rectangle(
              margin + fragment.x,
              pageSize.height - margin - localTop - fragment.height,
              fragment.width,
              fragment.height),
          fontCollection: fontCollection);
    }
    for (final fragment in displayList.textFragments) {
      final pageIndex = (fragment.baseline / usableHeight).floor();
      final canvas = await canvasAt(pageIndex);
      final baseline = fragment.baseline - pageIndex * usableHeight;
      canvas.beginText();
      canvas.setFillColor(_pdfColor(fragment.style.color));
      await canvas.setFontAndSize(
          await _resolveFont(fragment.style), fragment.style.fontSize);
      canvas
          .moveText(margin + fragment.x, pageSize.height - margin - baseline)
          // Each display-list fragment is written separately to preserve its
          // X coordinate and text style. Keep prose extractable across the
          // adjacent PDF text-show operations.
          .showText('${fragment.text} ')
          .endText();
      final target = fragment.linkTarget;
      if (target != null && target.isNotEmpty) {
        final textWidth = HtmlTextMeasure.text(fragment.text, fragment.style)
            .clamp(1.0, double.infinity)
            .toDouble();
        final textBaseline = pageSize.height - margin - baseline;
        await pages[pageIndex].addAnnotation(HtmlPdfLinkAnnotation(
          Rectangle(
              margin + fragment.x,
              textBaseline - fragment.style.fontSize * .25,
              textWidth,
              fragment.style.fontSize * 1.2),
          target,
        ));
      }
    }
  }

  DeviceRgb _pdfColor(CssColor color) =>
      DeviceRgb(color.red, color.green, color.blue);

  Future<PdfFont> _resolveFont(HtmlTextStyle style) async {
    final collection = fontCollection;
    if (collection != null) {
      final requested = style.fontFamily == null
          ? const <String>['sans-serif']
          : HtmlStandardFont.families(style.fontFamily!).toList();
      final face = await collection.resolve(BLFontQuery(
        requested.isEmpty ? const <String>['sans-serif'] : requested,
        weight: style.bold ? 700 : 400,
        slant: style.italic ? BLFontSlant.italic : BLFontSlant.normal,
      ));
      if (face != null && (face.hasTrueTypeOutlines || face.hasCFFOutlines)) {
        final cached = _embeddedFonts[face];
        if (cached != null) return cached;
        try {
          final font = PdfType0Font(TrueTypeFont.fromBytes(face.data));
          _embeddedFonts[face] = font;
          return font;
        } on Object {
          // Uma face legível pelo rasterizador pode usar uma variante que o
          // incorporador PDF ainda não aceita. Nesse caso o HTML segue válido.
        }
      }
    }
    return PdfFontFactory.createFont(HtmlStandardFont.resolve(style));
  }
}
