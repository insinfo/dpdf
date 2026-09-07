import 'package:dpdf/src/layout/element_property_container.dart';
import 'package:dpdf/src/layout/properties/leading.dart';
import 'package:dpdf/src/layout/element/block_content.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/layout/renderer/root_renderer.dart';
import 'package:dpdf/src/layout/property_container.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/element/div.dart';
import 'package:dpdf/src/layout/properties/text_alignment.dart';
import 'package:dpdf/src/layout/properties/vertical_alignment.dart';
import 'package:dpdf/src/layout/properties/horizontal_alignment.dart';
import 'package:dpdf/src/layout/properties/property.dart';

abstract class CraftRootElement<T extends CraftPropertyContainer>
    extends CraftElementPropertyContainer<T> {
  CraftPdfDocument pdfDocument;
  CraftRootRenderer? rootRenderer;
  bool immediateFlush = true;

  CraftRootElement(this.pdfDocument);

  Future<T> add(CraftBlockContent element) async {
    var renderer = element.createRendererSubTree();
    // In C#, CreateRendererSubTree returns IRenderer
    // We should add it to root renderer
    await ensureRootRendererNotNull().addChild(renderer!);
    return this as T;
  }

  CraftRootRenderer ensureRootRendererNotNull();

  Future<T> showTextAligned(
      {required String text,
      required double x,
      required double y,
      required CraftTextAlignment textAlign,
      CraftVerticalAlignment? vertAlign,
      double angle = 0,
      int pageNumber = 0}) async {
    CraftParagraph p = CraftParagraph();
    p.add(CraftText(text));
    p.setMargin(0);
    p.setProperty(
        CraftProperty.LEADING, CraftLeading(CraftLeading.MULTIPLIED, 1.0));

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
      {required CraftParagraph p,
      required double x,
      required double y,
      required CraftTextAlignment textAlign,
      CraftVerticalAlignment? vertAlign,
      double angle = 0,
      int pageNumber = 0}) async {
    if (pageNumber == 0) pageNumber = 1;

    CraftDiv div = CraftDiv();
    div.setTextAlignment(textAlign);
    if (vertAlign != null) {
      div.setVerticalAlignment(vertAlign);
    }
    if (angle != 0) {
      div.setRotationAngle(angle);
    }
    div.setProperty(CraftProperty.ROTATION_POINT_X, x);
    div.setProperty(CraftProperty.ROTATION_POINT_Y, y);

    double divSize = 5000;
    double divX = x;
    double divY = y;

    if (textAlign == CraftTextAlignment.center) {
      divX = x - divSize / 2;
      p.setHorizontalAlignment(CraftHorizontalAlignment.center);
    } else if (textAlign == CraftTextAlignment.right) {
      divX = x - divSize;
      p.setHorizontalAlignment(CraftHorizontalAlignment.right);
    }

    if (vertAlign == CraftVerticalAlignment.middle) {
      divY = y - divSize / 2;
    } else if (vertAlign == CraftVerticalAlignment.top) {
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
