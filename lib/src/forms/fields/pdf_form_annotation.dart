import 'dart:math' as math;

import '../../io/font/constants/standard_fonts.dart';
import '../../kernel/colors/color.dart';
import '../../kernel/colors/device_gray.dart';
import '../../kernel/colors/device_rgb.dart';
import '../../kernel/font/pdf_font.dart';
import '../../kernel/font/pdf_font_factory.dart';
import '../../kernel/geom/rectangle.dart';
import '../../kernel/pdf/annot/pdf_widget_annotation.dart';
import '../../kernel/pdf/canvas/pdf_canvas.dart';
import '../../kernel/pdf/pdf_array.dart';
import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_number.dart';
import '../../kernel/pdf/pdf_string.dart';
import '../../kernel/pdf/xobject/pdf_form_x_object.dart';
import 'abstract_pdf_form_field.dart';

/// Text style resolved from the default appearance string of a field
/// (ISO 32000-1, 12.7.3.3, Table 222).
class FieldTextStyle {
  final PdfFont font;
  final double fontSize;
  final Color color;

  const FieldTextStyle(this.font, this.fontSize, this.color);
}

/// A single widget annotation of a form field, able to build the appearance
/// stream that shows the field value (ISO 32000-1, 12.7.3.3 "Variable Text").
class PdfFormAnnotation extends AbstractPdfFormField {
  /// Inner padding kept between the annotation rectangle and the text, the
  /// same 1pt Acrobat uses when it regenerates an appearance.
  static const double innerPadding = 2;

  /// Ratio between the leading and the font size used for multiline fields.
  static const double multilineLeadingRatio = 1.2;

  PdfFormAnnotation(super.pdfObject);

  PdfWidgetAnnotation getWidget() {
    return PdfWidgetAnnotation(pdfRepresentation());
  }

  @override
  Future<bool> regenerateField() async {
    // A bare widget has no value of its own; the owning field drives the
    // regeneration and calls one of the draw* methods below.
    return false;
  }

  @override
  Future<List<String>> getAppearanceStates() async {
    final ap = await pdfRepresentation().dictionaryEntry(PdfName.ap);
    if (ap == null) return [];

    final n = await ap.dictionaryEntry(PdfName.n);
    if (n == null) return [];

    return n.keySet().map((e) => e.getValue()).toList();
  }

  Future<Rectangle?> getRectangle() async {
    PdfArray? rect = await pdfRepresentation().arrayEntry(PdfName.rect);
    final rectangle = await Rectangle.fromPdfArray(rect);
    if (rectangle == null) return null;
    // The array may list the corners in any order.
    return Rectangle(rectangle.getX(), rectangle.getY(),
        rectangle.getWidth().abs(), rectangle.getHeight().abs());
  }

  Future<Rectangle?> _getRect(PdfDictionary field) async {
    PdfArray? rect = await field.arrayEntry(PdfName.rect);
    return Rectangle.fromPdfArray(rect);
  }

  // ------------------------------------------------------------ text style

  /// Resolves font, size and colour from `/DA`, falling back to Helvetica and
  /// black as allowed by ISO 32000-1, 12.7.3.3.
  Future<FieldTextStyle> resolveTextStyle(
      {double autoSizeFor = 0,
      String sample = '',
      double availableWidth = 0}) async {
    await loadStyles();
    PdfFont font;
    try {
      font = resolveTypeface() ??
          PdfFontFactory.createFont(StandardFonts.HELVETICA);
    } catch (_) {
      font = PdfFontFactory.createFont(StandardFonts.HELVETICA);
    }
    double size = getFontSize();
    if (size <= 0) {
      size = autoSizeFor > 0
          ? computeAutoFontSize(font, sample, availableWidth, autoSizeFor)
          : AbstractPdfFormField.defaultFontSize.toDouble();
    }
    return FieldTextStyle(font, size, getColor() ?? DeviceGray.BLACK);
  }

  /// A zero size in `/DA` means the font shall be auto-sized as a function of
  /// the height of the annotation rectangle (ISO 32000-1, 12.7.3.3).
  static double computeAutoFontSize(
      PdfFont font, String text, double availableWidth, double availableHeight) {
    double size = availableHeight * 0.75;
    if (text.isNotEmpty && availableWidth > 0) {
      final unitWidth = font.getWidthPoint(text, 1.0);
      if (unitWidth > 0) {
        size = math.min(size, availableWidth / unitWidth);
      }
    }
    if (size < AbstractPdfFormField.minFontSize) {
      size = AbstractPdfFormField.minFontSize.toDouble();
    }
    return size;
  }

  /// Horizontal offset of [text] for the quadding code [quadding]
  /// (0 left, 1 centered, 2 right - ISO 32000-1, Table 222).
  static double alignmentOffset(
      PdfFont font, String text, double fontSize, double boxWidth, int quadding) {
    final textWidth = font.getWidthPoint(text, fontSize);
    switch (quadding) {
      case 1:
        return (boxWidth - textWidth) / 2;
      case 2:
        return boxWidth - innerPadding - textWidth;
      default:
        return innerPadding;
    }
  }

  // --------------------------------------------------------- appearance API

  /// Builds the appearance of a single line or multiline text field.
  ///
  /// The stream follows the layout of the example in ISO 32000-1, 12.7.3.3:
  /// `/Tx BMC q BT <DA> <Tm> <text> ET Q EMC`.
  Future<bool> drawTextFieldAndSaveAppearance(String value,
      {bool multiline = false,
      bool comb = false,
      int? maxLen,
      int quadding = 0,
      bool password = false}) async {
    final rect = await getRectangle();
    final doc = getDocument();
    if (rect == null || doc == null) return false;

    final width = rect.getWidth();
    final height = rect.getHeight();
    if (width <= 0 || height <= 0) return false;

    final shown = password ? '*' * value.length : value;
    final xObject = PdfFormXObject(Rectangle(0, 0, width, height));
    xObject.attachToDocument(doc);
    final canvas =
        PdfCanvas(xObject.pdfRepresentation(), await xObject.resourceDirectory(), doc);

    await _drawBoxDecorations(canvas, width, height);

    final style = await resolveTextStyle(
        autoSizeFor: multiline ? height / 3 : height,
        sample: multiline ? _longestLine(shown) : shown,
        availableWidth: width - 2 * innerPadding);

    await canvas.beginMarkedContent(PdfName('Tx'));
    canvas.saveState();
    canvas.rectangle(innerPadding / 2, innerPadding / 2, width - innerPadding,
        height - innerPadding);
    canvas.clip();
    canvas.newPath();
    canvas.beginText();
    await canvas.setFontAndSize(style.font, style.fontSize);
    canvas.setFillColor(style.color);

    if (comb && maxLen != null && maxLen > 0 && !multiline) {
      _writeComb(canvas, shown, style, width, height, maxLen);
    } else if (multiline) {
      _writeMultiline(canvas, shown, style, width, height, quadding);
    } else {
      _writeSingleLine(canvas, shown, style, width, height, quadding);
    }

    canvas.endText();
    canvas.restoreState();
    canvas.endMarkedContent();

    await _saveNormalAppearance(xObject);
    return true;
  }

  /// Builds the appearance of a choice field: a combo box shows the selected
  /// value on a single line, a list box shows the visible options starting at
  /// `/TI` and highlights the selected ones (ISO 32000-1, 12.7.4.4).
  Future<bool> drawChoiceFieldAndSaveAppearance(List<String> options,
      {List<int> selectedIndices = const [],
      int topIndex = 0,
      bool combo = false,
      int quadding = 0}) async {
    final rect = await getRectangle();
    final doc = getDocument();
    if (rect == null || doc == null) return false;

    final width = rect.getWidth();
    final height = rect.getHeight();
    if (width <= 0 || height <= 0) return false;

    final xObject = PdfFormXObject(Rectangle(0, 0, width, height));
    xObject.attachToDocument(doc);
    final canvas =
        PdfCanvas(xObject.pdfRepresentation(), await xObject.resourceDirectory(), doc);

    await _drawBoxDecorations(canvas, width, height);

    final selectedText = selectedIndices.isEmpty ||
            selectedIndices.first < 0 ||
            selectedIndices.first >= options.length
        ? ''
        : options[selectedIndices.first];

    final style = await resolveTextStyle(
        autoSizeFor: combo ? height : height / 3,
        sample: combo ? selectedText : _longest(options),
        availableWidth: width - 2 * innerPadding);

    if (!combo) {
      // Highlight of the selected rows is painted below the marked content.
      final lineHeight = style.fontSize * multilineLeadingRatio;
      for (final index in selectedIndices) {
        final row = index - topIndex;
        if (row < 0) continue;
        final y = height - (row + 1) * lineHeight;
        if (y + lineHeight < 0) continue;
        canvas.saveState();
        canvas.setFillColor(DeviceRgb(0.6, 0.756, 0.854));
        canvas.rectangle(innerPadding / 2, y, width - innerPadding, lineHeight);
        canvas.fill();
        canvas.restoreState();
      }
    }

    await canvas.beginMarkedContent(PdfName('Tx'));
    canvas.saveState();
    canvas.rectangle(innerPadding / 2, innerPadding / 2, width - innerPadding,
        height - innerPadding);
    canvas.clip();
    canvas.newPath();
    canvas.beginText();
    await canvas.setFontAndSize(style.font, style.fontSize);
    canvas.setFillColor(style.color);

    if (combo) {
      _writeSingleLine(canvas, selectedText, style, width, height, quadding);
    } else {
      final lineHeight = style.fontSize * multilineLeadingRatio;
      double y = height - innerPadding - style.fontSize;
      for (int i = topIndex; i < options.length; i++) {
        if (y < -lineHeight) break;
        final x = alignmentOffset(
            style.font, options[i], style.fontSize, width, quadding);
        canvas.setTextMatrixSimple(x, y);
        canvas.showText(options[i]);
        y -= lineHeight;
      }
    }

    canvas.endText();
    canvas.restoreState();
    canvas.endMarkedContent();

    await _saveNormalAppearance(xObject);
    return true;
  }

  /// Builds the on/off appearances of a check box (ISO 32000-1, 12.7.4.2.3).
  ///
  /// The off state is stored under the name `Off`; the on state uses
  /// [onStateName], `Yes` by convention.
  Future<bool> drawCheckBoxAndSaveAppearance(String onStateName,
      {bool checked = false, String checkCharacter = '4'}) async {
    final rect = await getRectangle();
    final doc = getDocument();
    if (rect == null || doc == null) return false;
    final width = rect.getWidth();
    final height = rect.getHeight();
    if (width <= 0 || height <= 0) return false;

    final off = PdfFormXObject(Rectangle(0, 0, width, height));
    off.attachToDocument(doc);
    final offCanvas =
        PdfCanvas(off.pdfRepresentation(), await off.resourceDirectory(), doc);
    await _drawBoxDecorations(offCanvas, width, height, defaultBorder: true);

    final on = PdfFormXObject(Rectangle(0, 0, width, height));
    on.attachToDocument(doc);
    final onCanvas =
        PdfCanvas(on.pdfRepresentation(), await on.resourceDirectory(), doc);
    await _drawBoxDecorations(onCanvas, width, height, defaultBorder: true);

    await loadStyles();
    final zapf = PdfFontFactory.createFont(StandardFonts.ZAPFDINGBATS);
    double size = getFontSize();
    if (size <= 0) {
      size = math.min(width, height) * 0.8;
      if (size < AbstractPdfFormField.minFontSize) {
        size = AbstractPdfFormField.minFontSize.toDouble();
      }
    }
    final color = getColor() ?? DeviceGray.BLACK;
    final textWidth = zapf.getWidthPoint(checkCharacter, size);

    await onCanvas.beginMarkedContent(PdfName('Tx'));
    onCanvas.saveState();
    onCanvas.beginText();
    await onCanvas.setFontAndSize(zapf, size);
    onCanvas.setFillColor(color);
    onCanvas.setTextMatrixSimple(
        (width - textWidth) / 2, (height - size * 0.7) / 2);
    onCanvas.showText(checkCharacter);
    onCanvas.endText();
    onCanvas.restoreState();
    onCanvas.endMarkedContent();

    final normal = PdfDictionary();
    normal.put(PdfName('Off'), off.pdfRepresentation());
    normal.put(PdfName(onStateName), on.pdfRepresentation());

    final appearance = PdfDictionary();
    appearance.put(PdfName.n, normal);
    put(PdfName.ap, appearance);
    put(PdfName.as, PdfName(checked ? onStateName : 'Off'));
    return true;
  }

  /// Builds the appearance of a pushbutton, whose caption comes from
  /// `/MK /CA` (ISO 32000-1, Table 189 and 12.7.4.2.2).
  Future<bool> drawPushButtonAndSaveAppearance([String? caption]) async {
    final rect = await getRectangle();
    final doc = getDocument();
    if (rect == null || doc == null) return false;
    final width = rect.getWidth();
    final height = rect.getHeight();
    if (width <= 0 || height <= 0) return false;

    String text = caption ?? '';
    if (caption == null) {
      final mk = await pdfRepresentation().dictionaryEntry(PdfName.mk);
      final ca = await mk?.stringEntry(PdfName.caUppercase);
      text = ca?.decodeMappingText() ?? '';
    }

    final xObject = PdfFormXObject(Rectangle(0, 0, width, height));
    xObject.attachToDocument(doc);
    final canvas =
        PdfCanvas(xObject.pdfRepresentation(), await xObject.resourceDirectory(), doc);
    await _drawBoxDecorations(canvas, width, height, defaultBorder: true);

    if (text.isNotEmpty) {
      final style = await resolveTextStyle(
          autoSizeFor: height,
          sample: text,
          availableWidth: width - 2 * innerPadding);
      await canvas.beginMarkedContent(PdfName('Tx'));
      canvas.saveState();
      canvas.beginText();
      await canvas.setFontAndSize(style.font, style.fontSize);
      canvas.setFillColor(style.color);
      final textWidth = style.font.getWidthPoint(text, style.fontSize);
      canvas.setTextMatrixSimple(
          (width - textWidth) / 2, (height - style.fontSize * 0.7) / 2);
      canvas.showText(text);
      canvas.endText();
      canvas.restoreState();
      canvas.endMarkedContent();
    }

    await _saveNormalAppearance(xObject);
    return true;
  }

  Future<void> drawRadioButtonAndSaveAppearance(String value) async {
    Rectangle? rect = await _getRect(pdfRepresentation());
    if (rect == null) return;

    // Draw Off state
    final xObjectOff =
        PdfFormXObject(Rectangle(0, 0, rect.getWidth(), rect.getHeight()));
    final doc = getDocument();
    if (doc == null) return;

    final canvasOff = PdfCanvas(xObjectOff.pdfRepresentation(),
        await xObjectOff.resourceDirectory(), doc);

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
    normalAppearance.put(PdfName("Off"), xObjectOff.pdfRepresentation());

    // Draw On state
    if (value != "Off") {
      final xObjectOn =
          PdfFormXObject(Rectangle(0, 0, rect.getWidth(), rect.getHeight()));
      final canvasOn = PdfCanvas(xObjectOn.pdfRepresentation(),
          await xObjectOn.resourceDirectory(), doc);

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

      normalAppearance.put(PdfName(value), xObjectOn.pdfRepresentation());
    }

    final widget = getWidget();
    PdfDictionary ap = PdfDictionary();
    ap.put(PdfName.n, normalAppearance);
    widget.put(PdfName.ap, ap);
  }

  // ------------------------------------------------------------- internals

  Future<void> _saveNormalAppearance(PdfFormXObject xObject) async {
    PdfDictionary? appearance =
        await pdfRepresentation().dictionaryEntry(PdfName.ap);
    if (appearance == null) {
      appearance = PdfDictionary();
      put(PdfName.ap, appearance);
    }
    appearance.put(PdfName.n, xObject.pdfRepresentation());
    appearance.markChanged();
    markChanged();
  }

  /// Paints the background and the border declared by the appearance
  /// characteristics dictionary `/MK` (ISO 32000-1, Table 189).
  Future<void> _drawBoxDecorations(
      PdfCanvas canvas, double width, double height,
      {bool defaultBorder = false}) async {
    final mk = await pdfRepresentation().dictionaryEntry(PdfName.mk);
    final background = await _colorFrom(mk, PdfName.bg);
    final border = await _colorFrom(mk, PdfName('BC'));

    double borderWidth = 1;
    final bs = await pdfRepresentation().dictionaryEntry(PdfName.bs);
    final w = await bs?.numberEntry(PdfName.w);
    if (w != null) borderWidth = w.doubleValue();

    if (background != null) {
      canvas.saveState();
      canvas.setFillColor(background);
      canvas.rectangle(0, 0, width, height);
      canvas.fill();
      canvas.restoreState();
    }
    final effectiveBorder =
        border ?? (defaultBorder ? DeviceGray.BLACK : null);
    if (effectiveBorder != null && borderWidth > 0) {
      canvas.saveState();
      canvas.setStrokeColor(effectiveBorder);
      canvas.setLineWidth(borderWidth);
      canvas.rectangle(borderWidth / 2, borderWidth / 2, width - borderWidth,
          height - borderWidth);
      canvas.stroke();
      canvas.restoreState();
    }
  }

  Future<Color?> _colorFrom(PdfDictionary? mk, PdfName key) async {
    if (mk == null) return null;
    final array = await mk.arrayEntry(key);
    if (array == null) return null;
    final components = <double>[];
    for (int i = 0; i < array.size(); i++) {
      final number = await array.get(i);
      if (number is PdfNumber) components.add(number.doubleValue());
    }
    switch (components.length) {
      case 1:
        return DeviceGray(components[0]);
      case 3:
        return DeviceRgb(components[0], components[1], components[2]);
      default:
        return null;
    }
  }

  void _writeSingleLine(PdfCanvas canvas, String text, FieldTextStyle style,
      double width, double height, int quadding) {
    if (text.isEmpty) return;
    final x =
        alignmentOffset(style.font, text, style.fontSize, width, quadding);
    final ascent = style.font.getAscent(text, style.fontSize);
    final descent = style.font.getDescent(text, style.fontSize);
    final y = (height - (ascent - descent)) / 2 - descent;
    canvas.setTextMatrixSimple(x, y);
    canvas.showText(text);
  }

  void _writeMultiline(PdfCanvas canvas, String text, FieldTextStyle style,
      double width, double height, int quadding) {
    final lines = wrapLines(
        text, style.font, style.fontSize, width - 2 * innerPadding);
    final leading = style.fontSize * multilineLeadingRatio;
    double y = height - innerPadding - style.fontSize;
    for (final line in lines) {
      if (y < -leading) break;
      final x =
          alignmentOffset(style.font, line, style.fontSize, width, quadding);
      canvas.setTextMatrixSimple(x, y);
      canvas.showText(line);
      y -= leading;
    }
  }

  /// Comb fields divide the rectangle in [maxLen] equally spaced cells and lay
  /// one character in each of them (ISO 32000-1, Table 228, bit 25).
  void _writeComb(PdfCanvas canvas, String text, FieldTextStyle style,
      double width, double height, int maxLen) {
    final cellWidth = width / maxLen;
    final ascent = style.font.getAscent(text.isEmpty ? 'X' : text, style.fontSize);
    final descent =
        style.font.getDescent(text.isEmpty ? 'X' : text, style.fontSize);
    final y = (height - (ascent - descent)) / 2 - descent;
    final count = math.min(text.length, maxLen);
    for (int i = 0; i < count; i++) {
      final ch = text[i];
      final chWidth = style.font.getWidthPoint(ch, style.fontSize);
      final x = i * cellWidth + (cellWidth - chWidth) / 2;
      canvas.setTextMatrixSimple(x, y);
      canvas.showText(ch);
    }
  }

  /// Breaks [text] into lines that fit [availableWidth], honouring the explicit
  /// line breaks already present in the value.
  static List<String> wrapLines(
      String text, PdfFont font, double fontSize, double availableWidth) {
    final result = <String>[];
    for (final paragraph in text.split(RegExp(r'\r\n|\r|\n'))) {
      if (paragraph.isEmpty) {
        result.add('');
        continue;
      }
      if (availableWidth <= 0 ||
          font.getWidthPoint(paragraph, fontSize) <= availableWidth) {
        result.add(paragraph);
        continue;
      }
      final words = paragraph.split(' ');
      var current = '';
      for (final word in words) {
        final candidate = current.isEmpty ? word : '$current $word';
        if (font.getWidthPoint(candidate, fontSize) <= availableWidth ||
            current.isEmpty) {
          current = candidate;
        } else {
          result.add(current);
          current = word;
        }
      }
      if (current.isNotEmpty) result.add(current);
    }
    return result;
  }

  static String _longestLine(String text) {
    String longest = '';
    for (final line in text.split(RegExp(r'\r\n|\r|\n'))) {
      if (line.length > longest.length) longest = line;
    }
    return longest;
  }

  static String _longest(List<String> values) {
    String longest = '';
    for (final value in values) {
      if (value.length > longest.length) longest = value;
    }
    return longest;
  }
}

/// Convenience access used by the field classes.
extension PdfFormAnnotationFactory on PdfWidgetAnnotation {
  PdfFormAnnotation asFormAnnotation() =>
      PdfFormAnnotation(pdfRepresentation());
}

/// Marks [dictionary] as belonging to [document] when it is not attached yet.
Future<void> ensureAttached(PdfDictionary dictionary, PdfDocument? document) async {
  if (document == null) return;
  if (dictionary.indirectHandle() == null) {
    dictionary.attachToDocument(document);
  }
}

/// Reads a text string entry, returning null when absent.
Future<String?> readText(PdfDictionary dictionary, PdfName key) async {
  final value = await dictionary.get(key, true);
  if (value is PdfString) return value.decodeMappingText();
  if (value is PdfName) return value.getValue();
  return null;
}
