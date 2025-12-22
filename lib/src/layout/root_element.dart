import 'package:itext/src/layout/element_property_container.dart';
import 'package:itext/src/layout/element/i_block_element.dart';
import 'package:itext/src/kernel/pdf/pdf_document.dart';
import 'package:itext/src/layout/renderer/root_renderer.dart';
import 'package:itext/src/layout/i_property_container.dart';

abstract class RootElement<T extends IPropertyContainer>
    extends ElementPropertyContainer<T> {
  PdfDocument pdfDocument;
  RootRenderer? rootRenderer;

  RootElement(this.pdfDocument);

  T add(IBlockElement element) {
    var renderer = element.createRendererSubTree();
    // In C#, CreateRendererSubTree returns IRenderer
    // We should add it to root renderer
    ensureRootRendererNotNull().addChild(renderer!);
    return this as T;
  }

  RootRenderer ensureRootRendererNotNull();

  void close();
}
