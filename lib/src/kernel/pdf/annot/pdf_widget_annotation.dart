import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';
import '../action/pdf_action.dart';
import 'pdf_annotation.dart';
import 'pdf_annotation_border.dart';

/// Appearance characteristics dictionary of a widget annotation.
///
/// See ISO 32000-1:2008, 12.5.6.19, Table 189.
class PdfAppearanceCharacteristics extends PdfObjectWrapper<PdfDictionary> {
  /// `/TP` value: caption only.
  static const int captionOnly = 0;

  /// `/TP` value: icon only.
  static const int iconOnly = 1;

  /// `/TP` value: caption below the icon.
  static const int captionBelowIcon = 2;

  /// `/TP` value: caption above the icon.
  static const int captionAboveIcon = 3;

  /// `/TP` value: caption to the right of the icon.
  static const int captionRightOfIcon = 4;

  /// `/TP` value: caption to the left of the icon.
  static const int captionLeftOfIcon = 5;

  /// `/TP` value: caption overlaid directly on the icon.
  static const int captionOverlaid = 6;

  PdfAppearanceCharacteristics(super.pdfObject);

  PdfAppearanceCharacteristics.create() : super(PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/R`, the rotation in counterclockwise degrees; a multiple of 90.
  PdfAppearanceCharacteristics setRotation(int degrees) {
    if (degrees % 90 != 0) {
      throw ArgumentError.value(
          degrees, 'degrees', 'Widget /MK /R shall be a multiple of 90');
    }
    pdfRepresentation().put(PdfName.r, PdfNumber.fromInt(degrees));
    return this;
  }

  /// Gets `/R`; the default is 0 per Table 189.
  Future<int> getRotation() async =>
      await pdfRepresentation().integerEntry(PdfName.r) ?? 0;

  /// Sets `/BC`, the border colour.
  PdfAppearanceCharacteristics setBorderColor(List<double> components) {
    pdfRepresentation()
        .put(PdfName.intern('BC'), PdfAnnotationColor.toArray(components));
    return this;
  }

  /// Gets `/BC`.
  Future<List<double>?> getBorderColor() =>
      PdfAnnotationColor.fromEntry(pdfRepresentation(), PdfName.intern('BC'));

  /// Sets `/BG`, the background colour.
  PdfAppearanceCharacteristics setBackgroundColor(List<double> components) {
    pdfRepresentation().put(PdfName.bg, PdfAnnotationColor.toArray(components));
    return this;
  }

  /// Gets `/BG`.
  Future<List<double>?> getBackgroundColor() =>
      PdfAnnotationColor.fromEntry(pdfRepresentation(), PdfName.bg);

  /// Sets `/CA`, the normal caption of a button field.
  PdfAppearanceCharacteristics setNormalCaption(String caption) {
    pdfRepresentation().put(PdfName.caUppercase, PdfString(caption));
    return this;
  }

  /// Gets `/CA`.
  Future<String?> getNormalCaption() async =>
      (await pdfRepresentation().stringEntry(PdfName.caUppercase))
          ?.decodeMappingText();

  /// Sets `/RC`, the rollover caption of a pushbutton field.
  PdfAppearanceCharacteristics setRolloverCaption(String caption) {
    pdfRepresentation().put(PdfName.intern('RC'), PdfString(caption));
    return this;
  }

  /// Sets `/AC`, the alternate (down) caption of a pushbutton field.
  PdfAppearanceCharacteristics setAlternateCaption(String caption) {
    pdfRepresentation().put(PdfName.intern('AC'), PdfString(caption));
    return this;
  }

  /// Sets `/TP`, the caption/icon layout of a pushbutton field.
  PdfAppearanceCharacteristics setTextPosition(int position) {
    if (position < captionOnly || position > captionOverlaid) {
      throw ArgumentError.value(
          position, 'position', 'Widget /MK /TP shall lie in [0, 6]');
    }
    pdfRepresentation().put(PdfName.intern('TP'), PdfNumber.fromInt(position));
    return this;
  }

  /// Gets `/TP`; the default is [captionOnly] per Table 189.
  Future<int> getTextPosition() async =>
      await pdfRepresentation().integerEntry(PdfName.intern('TP')) ??
      captionOnly;
}

/// Widget annotation.
///
/// See ISO 32000-1:2008, 12.5.6.19, Table 188.
class PdfWidgetAnnotation extends PdfAnnotation {
  static const int hidden = 1;
  static const int visibleButDoesNotPrint = 2;
  static const int hiddenButPrintable = 3;
  static const int visible = 4;

  PdfWidgetAnnotation(super.pdfObject);

  PdfWidgetAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.widget);
  }

  @override
  PdfName getSubtype() {
    return PdfName.widget;
  }

  PdfWidgetAnnotation setVisibility(int visibility) {
    switch (visibility) {
      case hidden:
        put(PdfName.f,
            PdfNumber.fromInt(PdfAnnotation.print | PdfAnnotation.hidden));
        break;
      case visibleButDoesNotPrint:
        // Visible (no Hidden/NoView) and No Print
        put(PdfName.f, PdfNumber.fromInt(0));
        break;
      case hiddenButPrintable:
        put(PdfName.f,
            PdfNumber.fromInt(PdfAnnotation.print | PdfAnnotation.noView));
        break;
      case visible:
      default:
        put(PdfName.f, PdfNumber.fromInt(PdfAnnotation.print));
        break;
    }
    return this;
  }

  PdfWidgetAnnotation setAction(PdfAction action) {
    put(PdfName.a, action.pdfRepresentation());
    return this;
  }

  Future<PdfWidgetAnnotation> setAdditionalAction(
      PdfName key, PdfAction action) async {
    await PdfAction.setAdditionalAction(this, key, action);
    return this;
  }

  /// Sets the parent dictionary.
  PdfWidgetAnnotation setParent(PdfDictionary parent) {
    put(PdfName.parent, parent);
    return this;
  }

  /// Gets the parent dictionary.
  Future<PdfDictionary?> getParent() async {
    return await pdfRepresentation().dictionaryEntry(PdfName.parent);
  }

  /// Sets the highlight mode.
  ///
  /// [mode] can be [highlightNone], [highlightInvert], [highlightOutline], or [highlightPush].
  PdfWidgetAnnotation setHighlightMode(PdfName mode) {
    put(PdfName.intern('H'), mode);
    return this;
  }

  /// Gets the highlight mode.
  Future<PdfName?> getHighlightMode() async {
    return await pdfRepresentation().nameEntry(PdfName.intern('H'));
  }

  /// Sets `/MK`, the appearance characteristics dictionary (Table 189).
  PdfWidgetAnnotation setAppearanceCharacteristics(
      PdfAppearanceCharacteristics characteristics) {
    put(PdfName.mk, characteristics.pdfRepresentation());
    return this;
  }

  /// Gets `/MK`.
  Future<PdfAppearanceCharacteristics?> getAppearanceCharacteristics() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.mk);
    return dictionary == null ? null : PdfAppearanceCharacteristics(dictionary);
  }

  /// Sets `/BS`, the border style dictionary (Table 166).
  PdfWidgetAnnotation setWidgetBorderStyle(PdfBorderStyle style) {
    put(PdfName.bs, style.pdfRepresentation());
    return this;
  }

  // Highlight modes
  static final PdfName highlightNone = PdfName.intern('N');
  static final PdfName highlightInvert = PdfName.intern('I');
  static final PdfName highlightOutline = PdfName.intern('O');
  static final PdfName highlightPush = PdfName.intern('P');
  static final PdfName highlightToggle = PdfName.intern('T');
}

/// Icon fit dictionary (`/MK /IF`) used by pushbutton widgets.
///
/// See ISO 32000-1:2008, 12.5.6.19, Table 247 referenced from Table 189.
class PdfIconFit extends PdfObjectWrapper<PdfDictionary> {
  /// `/SW` value: always scale.
  static final PdfName scaleAlways = PdfName.intern('A');

  /// `/SW` value: scale only when the icon is bigger than the annotation.
  static final PdfName scaleBigger = PdfName.intern('B');

  /// `/SW` value: scale only when the icon is smaller than the annotation.
  static final PdfName scaleSmaller = PdfName.intern('S');

  /// `/SW` value: never scale.
  static final PdfName scaleNever = PdfName.intern('N');

  /// `/S` value: anamorphic scaling.
  static final PdfName anamorphic = PdfName.intern('A');

  /// `/S` value: proportional scaling.
  static final PdfName proportional = PdfName.intern('P');

  PdfIconFit(super.pdfObject);

  PdfIconFit.create() : super(PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/SW`, the circumstances under which the icon is scaled.
  PdfIconFit setScaleWhen(PdfName when) {
    pdfRepresentation().put(PdfName.intern('SW'), when);
    return this;
  }

  /// Sets `/S`, the scaling type.
  PdfIconFit setScaleType(PdfName type) {
    pdfRepresentation().put(PdfName.s, type);
    return this;
  }

  /// Sets `/A`, the fractional positions of the icon inside the annotation.
  PdfIconFit setAlignment(double horizontal, double vertical) {
    pdfRepresentation()
        .put(PdfName.a, PdfArray.fromDoubles([horizontal, vertical]));
    return this;
  }
}
