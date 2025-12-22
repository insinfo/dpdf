import 'package:itext/src/layout/document.dart';
import 'package:itext/src/layout/renderer/root_renderer.dart';

class DocumentRenderer extends RootRenderer {
  final Document document;

  DocumentRenderer(this.document) : super();

  void close() {
    // flush
  }
}
