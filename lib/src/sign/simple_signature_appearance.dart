import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/xobject/pdf_form_x_object.dart';
import '../kernel/pdf/canvas/pdf_canvas.dart';
import '../kernel/font/pdf_font_factory.dart';
import '../kernel/geom/rectangle.dart';
import 'signature_field_appearance.dart';
import 'signer_properties.dart';

/// Builds the `/AP` `/N` form XObject of a visible signature field.
///
/// The layout is intentionally minimal: ISO 32000-1 12.7.4.5 leaves the
/// appearance to the signature handler, so only the values declared by
/// [SignerProperties.getSignatureAppearance] are painted.
class SimpleSignatureAppearance {
  final SignerProperties properties;

  SimpleSignatureAppearance(this.properties);

  /// The lines that [generate] paints, top to bottom.
  List<String> composeLines() {
    final appearance = properties.getSignatureAppearance();
    if (appearance.getMode() == SignatureAppearanceMode.empty) {
      return const [];
    }
    final lines = <String>[];
    if (appearance.getMode() == SignatureAppearanceMode.nameAndDescription) {
      final name = appearance.getSignerName();
      if (name != null && name.isNotEmpty) {
        lines.add(name);
      }
    }
    lines.addAll(appearance.getContentLines());
    if (appearance.isRenderingSignerProperties()) {
      if (properties.getReason().isNotEmpty) {
        lines.add('Reason: ${properties.getReason()}');
      }
      if (properties.getLocation().isNotEmpty) {
        lines.add('Location: ${properties.getLocation()}');
      }
      if (properties.getContact().isNotEmpty) {
        lines.add('Contact: ${properties.getContact()}');
      }
      lines.add('Date: '
          '${properties.getClaimedSignDate().toIso8601String().split('T')[0]}');
    }
    return lines;
  }

  Future<PdfFormXObject> generate(PdfDocument doc) async {
    final appearance = properties.getSignatureAppearance();
    final rect = properties.getPageRect();
    // Use the rect dimension for the BBox, but start at 0,0 for the Local Coordinate System
    final width = rect.getWidth();
    final height = rect.getHeight();
    final xObj = PdfFormXObject(Rectangle(0, 0, width, height));

    // Make the XObject indirect so it can be properly referenced
    xObj.pdfRepresentation().attachToDocument(doc);

    // Create canvas
    final canvas = await PdfCanvas.fromFormXObject(xObj, doc);

    final background = appearance.getBackgroundColor();
    if (background != null) {
      canvas
          .saveState()
          .setFillColor(background)
          .rectangle(0, 0, width, height)
          .fill()
          .restoreState();
    }

    final borderWidth = appearance.getBorderWidth();
    if (borderWidth > 0) {
      final inset = borderWidth / 2;
      canvas
          .saveState()
          .setStrokeColor(appearance.getBorderColor())
          .setLineWidth(borderWidth)
          .rectangle(inset, inset, width - borderWidth, height - borderWidth)
          .stroke()
          .restoreState();
    }

    final lines = composeLines();
    if (lines.isEmpty) {
      return xObj;
    }

    final font = PdfFontFactory.createFont('Helvetica');
    final fontSize = appearance.getFontSize();
    final leading = fontSize * 1.2;
    final margin = appearance.getMargin();
    final y = height - margin - fontSize; // Start from top

    canvas.saveState();
    canvas.setFillColor(appearance.getTextColor());
    canvas.beginText();
    await canvas.setFontAndSize(font, fontSize);
    canvas.setLeading(leading);
    canvas.moveText(margin, y);
    for (var index = 0; index < lines.length; index++) {
      if (index > 0) {
        canvas.newlineText();
      }
      canvas.showText(lines[index]);
    }
    canvas.endText();
    canvas.restoreState();

    return xObj;
  }
}
