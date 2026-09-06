import 'dart:math' as math;

import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_array.dart';
import '../../kernel/pdf/annot/pdf_widget_annotation.dart';
import 'abstract_pdf_form_field.dart';
import '../../kernel/geom/rectangle.dart';
import '../../kernel/pdf/xobject/pdf_form_x_object.dart';
import '../../kernel/pdf/canvas/pdf_canvas.dart';
import '../../kernel/colors/device_gray.dart';

class PdfFormAnnotation extends AbstractPdfFormField {
  PdfFormAnnotation(PdfDictionary pdfObject) : super(pdfObject);

  PdfWidgetAnnotation getWidget() {
    return PdfWidgetAnnotation(getPdfObject());
  }

  @override
  Future<bool> regenerateField() async {
    // Appearance regeneration is handled by specific field types or manually.
    return false;
  }

  @override
  Future<List<String>> getAppearanceStates() async {
    final ap = await getPdfObject().getAsDictionary(PdfName.ap);
    if (ap == null) return [];

    final n = await ap.getAsDictionary(PdfName.n);
    if (n == null) return [];

    return n.keySet().map((e) => e.getValue()).toList();
  }

  Future<Rectangle?> _getRect(PdfDictionary field) async {
    PdfArray? rect = await field.getAsArray(PdfName.rect);
    return Rectangle.fromPdfArray(rect);
  }

  Future<void> drawRadioButtonAndSaveAppearance(String value) async {
    Rectangle? rect = await _getRect(getPdfObject());
    if (rect == null) return;

    // Draw Off state
    final xObjectOff =
        PdfFormXObject(Rectangle(0, 0, rect.getWidth(), rect.getHeight()));
    final doc = await getDocument();
    if (doc == null) return;

    final canvasOff = PdfCanvas(
        xObjectOff.getPdfObject(), await xObjectOff.getResources(), doc);

    double radius = math.min(rect.getWidth(), rect.getHeight()) / 2;
    double cx = rect.getWidth() / 2;
    double cy = rect.getHeight() / 2;

    // Draw circle border (Off)
    canvasOff.saveState();
    canvasOff.setStrokeColor(DeviceGray.BLACK);
    canvasOff.setLineWidth(1);
    canvasOff.circle(cx, cy, radius - 1);
    canvasOff.stroke();
    canvasOff.restoreState();

    PdfDictionary normalAppearance = PdfDictionary();
    normalAppearance.put(PdfName("Off"), xObjectOff.getPdfObject());

    // Draw On state
    if (value != "Off") {
      final xObjectOn =
          PdfFormXObject(Rectangle(0, 0, rect.getWidth(), rect.getHeight()));
      final canvasOn = PdfCanvas(
          xObjectOn.getPdfObject(), await xObjectOn.getResources(), doc);

      // Draw circle border
      canvasOn.saveState();
      canvasOn.setStrokeColor(DeviceGray.BLACK);
      canvasOn.setLineWidth(1);
      canvasOn.circle(cx, cy, radius - 1);
      canvasOn.stroke();

      // Draw filled dot
      canvasOn.setFillColor(DeviceGray.BLACK);
      canvasOn.circle(cx, cy, radius / 2); // 50% dot
      canvasOn.fill();
      canvasOn.restoreState();

      normalAppearance.put(PdfName(value), xObjectOn.getPdfObject());
    }

    final widget = getWidget();
    PdfDictionary ap = PdfDictionary();
    ap.put(PdfName.n, normalAppearance);
    widget.put(PdfName.ap, ap);
  }
}
