import '../../kernel/geom/rectangle.dart';
import '../../kernel/pdf/action/pdf_action_uri.dart';
import '../../kernel/pdf/annot/pdf_annotation.dart';
import '../../kernel/pdf/pdf_array.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_number.dart';

/// Invisible URI link annotation created for visible HTML anchor text.
class CraftHtmlPdfLinkAnnotation extends CraftPdfAnnotation {
  CraftHtmlPdfLinkAnnotation(CraftRectangle rectangle, String target)
      : super.fromRect(rectangle) {
    put(CraftPdfName.subtype, CraftPdfName.link);
    put(CraftPdfName.a, PdfActionURI.createURI(target).pdfRepresentation());
    // A zero-width border keeps the text presentation controlled by CSS.
    put(
        CraftPdfName.border,
        CraftPdfArray.fromList([
          CraftPdfNumber.fromInt(0),
          CraftPdfNumber.fromInt(0),
          CraftPdfNumber.fromInt(0),
        ]));
  }

  @override
  CraftPdfName getSubtype() => CraftPdfName.link;
}
