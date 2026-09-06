import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/xobject/pdf_form_x_object.dart';
import '../kernel/pdf/canvas/pdf_canvas.dart';
import '../kernel/font/pdf_font_factory.dart';
import '../kernel/geom/rectangle.dart';
import '../kernel/colors/device_gray.dart'; 
import 'signer_properties.dart';

/// Helper class to generate a simple visual appearance for signatures.
///  TODO This replaces the heavy dependency on the full Layout module for now.
class SimpleSignatureAppearance {
  final SignerProperties properties;

  SimpleSignatureAppearance(this.properties);

  Future<PdfFormXObject> generate(PdfDocument doc) async {
    final rect = properties.getPageRect();
    // Use the rect dimension for the BBox, but start at 0,0 for the Local Coordinate System
    final width = rect.getWidth();
    final height = rect.getHeight();
    final xObj = PdfFormXObject(Rectangle(0, 0, width, height));
    
    // Make the XObject indirect so it can be properly referenced
    xObj.getPdfObject().makeIndirect(doc);
    
    // Create canvas
    final canvas = await PdfCanvas.fromFormXObject(xObj, doc);
    
    // Draw Background (Light Gray)
    canvas.saveState()
        .setFillColor(DeviceGray(0.9))
        .rectangle(0, 0, width, height)
        .fill()
        .restoreState();

    // Draw Border (Dark Gray)
    canvas.saveState()
        .setStrokeColor(DeviceGray(0.5))
        .setLineWidth(1)
        .rectangle(0.5, 0.5, width - 1, height - 1)
        .stroke()
        .restoreState();

    // Prepare Text
    final font = await PdfFontFactory.createFont('Helvetica');
    // if (font != null) { // Removed check
      double fontSize = 10;
      double leading = 12;
      double margin = 5;
      double y = height - margin - fontSize; // Start from top

      canvas.beginText();
      await canvas.setFontAndSize(font, fontSize);
      canvas.setLeading(leading);
      canvas.moveText(margin, y);
      
      // Signer Name (Simulation) or Reason/Location
      
      if (properties.getReason().isNotEmpty) {
        canvas.showText("Reason: ${properties.getReason()}");
        canvas.newlineText();
      }
      
      if (properties.getLocation().isNotEmpty) {
        canvas.showText("Location: ${properties.getLocation()}");
        canvas.newlineText();
      }
      
      if (properties.getContact().isNotEmpty) {
        canvas.showText("Contact: ${properties.getContact()}");
        canvas.newlineText();
      }

      canvas.showText("Date: ${properties.getClaimedSignDate().toIso8601String().split('T')[0]}");
      
      canvas.endText();


    return xObj;
  }
}
