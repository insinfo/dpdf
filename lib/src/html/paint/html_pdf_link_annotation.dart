import '../../kernel/pdf/action/pdf_action_uri.dart';
import '../../kernel/pdf/annot/pdf_annotation.dart';
import '../../kernel/pdf/pdf_array.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_number.dart';

/// Invisible URI link annotation created for visible HTML anchor text.
class HtmlPdfLinkAnnotation extends PdfAnnotation {
  HtmlPdfLinkAnnotation(super.rectangle, String target) : super.fromRect() {
    put(PdfName.subtype, PdfName.link);
    put(PdfName.a, PdfActionURI.createURI(target).pdfRepresentation());
    // A zero-width border keeps the text presentation controlled by CSS.
    put(
        PdfName.border,
        PdfArray.fromList([
          PdfNumber.fromInt(0),
          PdfNumber.fromInt(0),
          PdfNumber.fromInt(0),
        ]));
  }

  @override
  PdfName getSubtype() => PdfName.link;
}
