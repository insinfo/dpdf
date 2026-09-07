import '../layout/html_display_list.dart';
import '../css/css_color.dart';
import '../../kernel/colors/device_rgb.dart';
import 'html_standard_font.dart';
import '../../kernel/font/pdf_font_factory.dart';
import '../../kernel/geom/page_size.dart';
import '../../kernel/geom/rectangle.dart';
import '../../kernel/pdf/canvas/pdf_canvas.dart';
import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/pdf/pdf_page.dart';
import 'html_pdf_link_annotation.dart';

/// Paints the platform-neutral HTML display list into paginated PDF pages.
class CraftHtmlPdfPainter {
  final CraftPdfDocument document;
  final CraftPageSize pageSize;
  final double margin;

  const CraftHtmlPdfPainter(this.document, this.pageSize, this.margin);

  Future<void> paint(CraftHtmlDisplayList displayList) async {
    final usableHeight = pageSize.height - margin * 2;
    final canvases = <CraftPdfCanvas>[];
    final pages = <CraftPdfPage>[];
    Future<CraftPdfCanvas> canvasAt(int pageIndex) async {
      while (canvases.length <= pageIndex) {
        final page = await document.appendBlankPage(pageSize);
        pages.add(page);
        canvases.add(await CraftPdfCanvas.fromPage(page));
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
    for (final fragment in displayList.textFragments) {
      final pageIndex = (fragment.baseline / usableHeight).floor();
      final canvas = await canvasAt(pageIndex);
      final baseline = fragment.baseline - pageIndex * usableHeight;
      canvas.beginText();
      canvas.setFillColor(_pdfColor(fragment.style.color));
      await canvas.setFontAndSize(
          CraftPdfFontFactory.createFont(
              CraftHtmlStandardFont.resolve(fragment.style)),
          fragment.style.fontSize);
      canvas
          .moveText(margin + fragment.x, pageSize.height - margin - baseline)
          // Each display-list fragment is written separately to preserve its
          // X coordinate and text style. Keep prose extractable across the
          // adjacent PDF text-show operations.
          .showText('${fragment.text} ')
          .endText();
      final target = fragment.linkTarget;
      if (target != null && target.isNotEmpty) {
        final textWidth = (fragment.text.length * fragment.style.fontSize * .52)
            .clamp(1.0, double.infinity)
            .toDouble();
        final textBaseline = pageSize.height - margin - baseline;
        await pages[pageIndex].addAnnotation(CraftHtmlPdfLinkAnnotation(
          CraftRectangle(
              margin + fragment.x,
              textBaseline - fragment.style.fontSize * .25,
              textWidth,
              fragment.style.fontSize * 1.2),
          target,
        ));
      }
    }
  }

  CraftDeviceRgb _pdfColor(CraftCssColor color) =>
      CraftDeviceRgb(color.red, color.green, color.blue);
}
