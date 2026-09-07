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

class CraftPdfFormAnnotation extends CraftAbstractPdfFormField {
  CraftPdfFormAnnotation(super.pdfObject);

  CraftPdfWidgetAnnotation getWidget() {
    return CraftPdfWidgetAnnotation(pdfRepresentation());
  }

  @override
  Future<bool> regenerateField() async {
    // Appearance regeneration is handled by specific field types or manually.
    return false;
  }

  @override
  Future<List<String>> getAppearanceStates() async {
    final ap = await pdfRepresentation().dictionaryEntry(CraftPdfName.ap);
    if (ap == null) return [];

    final n = await ap.dictionaryEntry(CraftPdfName.n);
    if (n == null) return [];

    return n.keySet().map((e) => e.getValue()).toList();
  }

  Future<CraftRectangle?> _getRect(CraftPdfDictionary field) async {
    CraftPdfArray? rect = await field.arrayEntry(CraftPdfName.rect);
    return CraftRectangle.fromPdfArray(rect);
  }

  Future<void> drawRadioButtonAndSaveAppearance(String value) async {
    CraftRectangle? rect = await _getRect(pdfRepresentation());
    if (rect == null) return;

    // Draw Off state
    final xObjectOff = CraftPdfFormXObject(
        CraftRectangle(0, 0, rect.getWidth(), rect.getHeight()));
    final doc = getDocument();
    if (doc == null) return;

    final canvasOff = CraftPdfCanvas(xObjectOff.pdfRepresentation(),
        await xObjectOff.resourceDirectory(), doc);

    double radius = math.min(rect.getWidth(), rect.getHeight()) / 2;
    double cx = rect.getWidth() / 2;
    double cy = rect.getHeight() / 2;

    // Draw circle border (Off)
    canvasOff.saveState();
    canvasOff.setStrokeColor(CraftDeviceGray.BLACK);
    canvasOff.setLineWidth(1);
    canvasOff.circle(cx, cy, radius - 1);
    canvasOff.stroke();
    canvasOff.restoreState();

    CraftPdfDictionary normalAppearance = CraftPdfDictionary();
    normalAppearance.put(CraftPdfName("Off"), xObjectOff.pdfRepresentation());

    // Draw On state
    if (value != "Off") {
      final xObjectOn = CraftPdfFormXObject(
          CraftRectangle(0, 0, rect.getWidth(), rect.getHeight()));
      final canvasOn = CraftPdfCanvas(xObjectOn.pdfRepresentation(),
          await xObjectOn.resourceDirectory(), doc);

      // Draw circle border
      canvasOn.saveState();
      canvasOn.setStrokeColor(CraftDeviceGray.BLACK);
      canvasOn.setLineWidth(1);
      canvasOn.circle(cx, cy, radius - 1);
      canvasOn.stroke();

      // Draw filled dot
      canvasOn.setFillColor(CraftDeviceGray.BLACK);
      canvasOn.circle(cx, cy, radius / 2); // 50% dot
      canvasOn.fill();
      canvasOn.restoreState();

      normalAppearance.put(CraftPdfName(value), xObjectOn.pdfRepresentation());
    }

    final widget = getWidget();
    CraftPdfDictionary ap = CraftPdfDictionary();
    ap.put(CraftPdfName.n, normalAppearance);
    widget.put(CraftPdfName.ap, ap);
  }
}
