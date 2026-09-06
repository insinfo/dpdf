import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/canvas/pdf_canvas.dart';

class CraftDrawContext {
  CraftPdfDocument document;
  CraftPdfCanvas canvas;
  bool taggingEnabled = false;

  CraftDrawContext(this.document, this.canvas, [this.taggingEnabled = false]);

  CraftPdfDocument getDocument() {
    return document;
  }

  CraftPdfCanvas getCanvas() {
    return canvas;
  }

  bool isTaggingEnabled() {
    return taggingEnabled;
  }

  void setTaggingEnabled(bool taggingEnabled) {
    this.taggingEnabled = taggingEnabled;
  }
}
