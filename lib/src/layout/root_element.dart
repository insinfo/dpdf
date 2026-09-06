import 'package:dpdf/src/layout/element_property_container.dart';
import 'package:dpdf/src/layout/properties/leading.dart';
import 'package:dpdf/src/layout/element/i_block_element.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/layout/renderer/root_renderer.dart';
import 'package:dpdf/src/layout/i_property_container.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/element/div.dart';
import 'package:dpdf/src/layout/properties/text_alignment.dart';
import 'package:dpdf/src/layout/properties/vertical_alignment.dart';
import 'package:dpdf/src/layout/properties/horizontal_alignment.dart';
import 'package:dpdf/src/layout/properties/property.dart';

abstract class RootElement<T extends IPropertyContainer>
    extends ElementPropertyContainer<T> {
  PdfDocument pdfDocument;
  RootRenderer? rootRenderer;
  bool immediateFlush = true;

  RootElement(this.pdfDocument);

  Future<T> add(IBlockElement element) async {
    var renderer = element.createRendererSubTree();
    // In C#, CreateRendererSubTree returns IRenderer
    // We should add it to root renderer
    await ensureRootRendererNotNull().addChild(renderer!);
    return this as T;
  }

  RootRenderer ensureRootRendererNotNull();

  Future<T> showTextAligned(
      {required String text,
      required double x,
      required double y,
      required TextAlignment textAlign,
      VerticalAlignment? vertAlign,
      double angle = 0,
      int pageNumber = 0}) async {
    Paragraph p = Paragraph();
    p.add(Text(text));
    p.setMargin(0);
    p.setProperty(Property.LEADING, Leading(Leading.MULTIPLIED, 1.0));

    return await showTextAlignedParagraph(
        p: p,
        x: x,
        y: y,
        textAlign: textAlign,
        vertAlign: vertAlign,
        angle: angle,
        pageNumber: pageNumber);
  }

  Future<T> showTextAlignedParagraph(
      {required Paragraph p,
      required double x,
      required double y,
      required TextAlignment textAlign,
      VerticalAlignment? vertAlign,
      double angle = 0,
      int pageNumber = 0}) async {
    if (pageNumber == 0) pageNumber = 1;

    Div div = Div();
    div.setTextAlignment(textAlign);
    if (vertAlign != null) {
      div.setVerticalAlignment(vertAlign);
    }
    if (angle != 0) {
      div.setRotationAngle(angle);
    }
    div.setProperty(Property.ROTATION_POINT_X, x);
    div.setProperty(Property.ROTATION_POINT_Y, y);

    double divSize = 5000;
    double divX = x;
    double divY = y;

    if (textAlign == TextAlignment.center) {
      divX = x - divSize / 2;
      p.setHorizontalAlignment(HorizontalAlignment.center);
    } else if (textAlign == TextAlignment.right) {
      divX = x - divSize;
      p.setHorizontalAlignment(HorizontalAlignment.right);
    }

    if (vertAlign == VerticalAlignment.middle) {
      divY = y - divSize / 2;
    } else if (vertAlign == VerticalAlignment.top) {
      // Check enum case
      divY = y - divSize;
    }

    div.setFixedPosition(pageNumber, divX, divY, divSize);
    div.setMinHeight(divSize);

    // TODO: Check accessibility properties role

    div.add(p);
    await add(div);
    return this as T;
  }

  Future<void> close();
}
