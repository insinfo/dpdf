import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';

class DrawContext {
  PdfDocument document;
  PdfCanvas canvas;
  bool taggingEnabled = false;

  DrawContext(this.document, this.canvas, [this.taggingEnabled = false]);

  PdfDocument getDocument() {
    return document;
  }

  PdfCanvas getCanvas() {
    return canvas;
  }

  bool isTaggingEnabled() {
    return taggingEnabled;
  }

  void setTaggingEnabled(bool taggingEnabled) {
    this.taggingEnabled = taggingEnabled;
  }
}
