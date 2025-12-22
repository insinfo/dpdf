import 'package:dpdf/src/io/font/otf/glyph_line.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/text_layout_result.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/kernel/font/pdf_font.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

class TextRenderer extends AbstractRenderer {
  late String text;
  GlyphLine? line;

  TextRenderer(Text textElement, [String text = ""]) : super(textElement) {
    this.text = text.isEmpty ? textElement.getText() : text;
  }

  TextRenderer.fromTextRenderer(TextRenderer other)
      : super(other.getModelElement()) {
    this.text = other.text;
    this.line = other.line;
  }

  @override
  Text getModelElement() {
    return super.getModelElement() as Text;
  }

  @override
  MinMaxWidth? getMinMaxWidth() {
    if (line == null) {
      PdfFont? font = getProperty(Property.FONT);
      if (font != null) {
        line = font.createGlyphLine(text);
      }
    }
    if (line == null) return MinMaxWidth(0);

    UnitValue? fontSizeVal = getProperty(Property.FONT_SIZE);
    double fontSize = fontSizeVal?.getValue() ?? 12.0;

    double minW = 0;
    double maxW = 0;
    double currentWordW = 0;

    int start = line!.getStart();
    int end = line!.getEnd();

    for (int i = start; i < end; i++) {
      var glyph = line!.get(i);
      double w = glyph.getWidth() * fontSize / 1000.0;

      if (glyph.getUnicode() == 32) {
        // Space
        if (currentWordW > minW) minW = currentWordW;
        currentWordW = 0;
      } else {
        currentWordW += w;
      }
      maxW += w;
    }
    if (currentWordW > minW) minW = currentWordW;

    return MinMaxWidth.full(minW, maxW, 0);
  }

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    LayoutArea area = layoutContext.getArea();
    Rectangle layoutBox = area.getBBox().clone();

    // Box model
    double parentWidth = layoutBox.getWidth();
    double mt = getResolvedProperty(Property.MARGIN_TOP, parentWidth);
    double mb = getResolvedProperty(Property.MARGIN_BOTTOM, parentWidth);
    double ml = getResolvedProperty(Property.MARGIN_LEFT, parentWidth);
    double mr = getResolvedProperty(Property.MARGIN_RIGHT, parentWidth);

    double pt = getResolvedProperty(Property.PADDING_TOP, parentWidth);
    double pb = getResolvedProperty(Property.PADDING_BOTTOM, parentWidth);
    double pl = getResolvedProperty(Property.PADDING_LEFT, parentWidth);
    double pr = getResolvedProperty(Property.PADDING_RIGHT, parentWidth);

    // Borders simplify (check AbstractRenderer helpers if I added them? no, manual getProperty)
    // For text usually borders are thin.
    // Ignored for calculation simplicity or assume BlockRenderer handles if wrapper.
    // But if TextRenderer is standalone, it needs it.
    // Let's assume simplest:
    double leftOffset = ml + pl;
    double rightOffset = mr + pr;
    double topOffset = mt + pt;
    double bottomOffset = mb + pb;

    PdfFont? font = getProperty(Property.FONT);
    UnitValue? fontSizeVal = getProperty(Property.FONT_SIZE);
    double fontSize = fontSizeVal?.getValue() ?? 12.0;

    if (font == null) {
      return TextLayoutResult(
          LayoutResult.NOTHING, occupiedArea, null, null, this);
    }

    if (line == null) {
      line = font.createGlyphLine(text);
    }

    double currentLineWidth = 0;
    int splitIndex = -1;
    double maxWidth = layoutBox.getWidth() - leftOffset - rightOffset;
    if (maxWidth < 0) maxWidth = 0;

    bool wordSplit = false;

    int start = line!.getStart();
    int end = line!.getEnd();

    for (int i = start; i < end; i++) {
      var glyph = line!.get(i);
      double glyphWidth = glyph.getWidth() * fontSize / 1000.0;

      if (currentLineWidth + glyphWidth > maxWidth) {
        splitIndex = i;
        wordSplit = true;
        break;
      }
      currentLineWidth += glyphWidth;
    }

    if (splitIndex != -1) {
      if (splitIndex == start) {
        return TextLayoutResult(
            LayoutResult.NOTHING, occupiedArea, null, null, this);
      }

      TextRenderer split1 = TextRenderer.fromTextRenderer(this);
      split1.line = GlyphLine.copySlice(line!, start, splitIndex);
      split1.text = split1.line.toString();

      TextRenderer overflow = TextRenderer.fromTextRenderer(this);
      overflow.line = GlyphLine.copySlice(line!, splitIndex, end);
      overflow.text = overflow.line.toString();

      LayoutArea occupied = LayoutArea(
          area.getPageNumber(),
          Rectangle(
              layoutBox.getX(),
              layoutBox.getY() +
                  layoutBox.getHeight() -
                  fontSize -
                  topOffset, // Adjusted Y?
              currentLineWidth + leftOffset + rightOffset,
              fontSize + topOffset + bottomOffset));

      // occupiedArea usually includes margins/padding.
      // But draw needs to know where TEXT starts.
      // We start text at x + leftOffset, y - topOffset.

      return TextLayoutResult(LayoutResult.PARTIAL, occupied, split1, overflow)
          .setWordHasBeenSplit(wordSplit);
    } else {
      LayoutArea occupied = LayoutArea(
          area.getPageNumber(),
          Rectangle(
              layoutBox.getX(),
              layoutBox.getY() +
                  layoutBox.getHeight() -
                  fontSize -
                  topOffset -
                  bottomOffset, // Height consumed
              currentLineWidth + leftOffset + rightOffset,
              fontSize + topOffset + bottomOffset));

      return TextLayoutResult(LayoutResult.FULL, occupied, null, null);
    }
  }

  @override
  Future<void> draw(DrawContext drawContext) async {
    // Draw background/borders first
    await super.draw(drawContext);

    if (line == null) return;

    PdfFont? font = getProperty(Property.FONT);
    UnitValue? fontSizeVal = getProperty(Property.FONT_SIZE);

    // Calculate content position
    // Occupied area includes margins.
    // Text starts at occArea.x + ml + pl, occArea.y + mb + pb?
    // Wait, coordinate system.
    // PDF Y is bottom-up.
    // If occupiedArea moves DOWN from top:
    // occArea.y is the BOTTOM of the area.
    // Text baseline...
    // Let's assume simple baseline usage = occArea.y + bottomOffset?

    double parentWidth = 0; // Don't have it easily.
    // Re-resolve or assume stored?
    // Let's re-resolve.
    if (occupiedArea != null) {
      parentWidth = occupiedArea!.getBBox().getWidth();
    }

    double ml = getResolvedProperty(Property.MARGIN_LEFT, parentWidth);
    double pl = getResolvedProperty(Property.PADDING_LEFT, parentWidth);
    double mb = getResolvedProperty(Property.MARGIN_BOTTOM, parentWidth);
    double pb = getResolvedProperty(Property.PADDING_BOTTOM, parentWidth);

    double x = (occupiedArea?.getBBox().getX() ?? 0) + ml + pl;
    double y = (occupiedArea?.getBBox().getY() ?? 0) + mb + pb;
    // Note: simple text vertical alignment (baseline) is tricky.
    // Usually we add descent?
    // For now align bottom of text box to y + mb + pb.

    var canvas = drawContext.getCanvas();
    canvas.beginText();
    await canvas.setFontAndSize(font!, fontSizeVal?.getValue() ?? 12);
    canvas.moveText(x, y).showText(text).endText();
  }
}
