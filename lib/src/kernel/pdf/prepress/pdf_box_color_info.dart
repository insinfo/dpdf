import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object_wrapper.dart';
import 'pdf_page_boundaries.dart';

/// The guideline style of `/S` in a box style dictionary.
///
/// ISO 32000-1:2008, Table 361. "Other guideline styles may be defined in the
/// future", so an unrecognised name is reported as [unknown] rather than
/// rejected.
enum PdfBoxGuidelineStyle {
  /// `/S`, a solid rectangle. The default value.
  solid,

  /// `/D`, a dashed rectangle; the pattern comes from the `/D` entry.
  dashed,

  /// A style this version of the specification does not define.
  unknown,
}

/// A box style dictionary.
///
/// ISO 32000-1:2008, 14.11.2.2 "Display of Page Boundaries", Table 361. It
/// describes how a conforming reader should draw the guideline for one page
/// boundary. Every entry is optional and carries a default.
class PdfBoxStyle extends PdfObjectWrapper<PdfDictionary> {
  /// `/C`, the DeviceRGB colour of the guideline.
  static final PdfName colour = PdfName.intern('C');

  /// `/W`, the guideline width.
  static final PdfName width = PdfName.intern('W');

  /// `/S`, the guideline style.
  static final PdfName style = PdfName.intern('S');

  /// `/D`, the dash array of a dashed guideline.
  static final PdfName dashArray = PdfName.intern('D');

  /// The default of `/C`: black.
  static const List<double> defaultColour = [0.0, 0.0, 0.0];

  /// The default of `/W`.
  static const double defaultWidth = 1.0;

  /// The default of `/D`.
  static const List<double> defaultDashArray = [3.0];

  PdfBoxStyle(super.pdfObject);

  /// Creates an empty box style dictionary; every entry then has its default
  /// value from Table 361.
  PdfBoxStyle.create() : super(PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/C`, three DeviceRGB components in the range 0.0 to 1.0.
  PdfBoxStyle setColour(List<double> rgb) {
    if (rgb.length != 3) {
      throw ArgumentError.value(rgb, 'rgb',
          'A box style /C shall be an array of three numbers (Table 361)');
    }
    for (final component in rgb) {
      if (component < 0.0 || component > 1.0) {
        throw ArgumentError.value(rgb, 'rgb',
            'A box style /C component shall be in the range 0.0 to 1.0');
      }
    }
    pdfRepresentation().put(colour, PdfArray.fromDoubles(rgb));
    return this;
  }

  /// Gets `/C`; the default is black.
  Future<List<double>> getColour() async =>
      await _numbers(colour) ?? defaultColour;

  /// Sets `/W`, the guideline width in default user space units.
  PdfBoxStyle setWidth(double value) {
    if (value < 0) {
      throw ArgumentError.value(
          value, 'value', 'A box style /W shall not be negative');
    }
    pdfRepresentation().put(width, PdfNumber(value));
    return this;
  }

  /// Gets `/W`; the default is 1.
  Future<double> getWidth() async =>
      (await pdfRepresentation().numberEntry(width))?.doubleValue() ??
      defaultWidth;

  /// Sets `/S`.
  ///
  /// [PdfBoxGuidelineStyle.unknown] cannot be written; use [setStyleName] to
  /// record a style defined by a later specification.
  PdfBoxStyle setStyle(PdfBoxGuidelineStyle value) {
    switch (value) {
      case PdfBoxGuidelineStyle.solid:
        return setStyleName(PdfName.intern('S'));
      case PdfBoxGuidelineStyle.dashed:
        return setStyleName(PdfName.intern('D'));
      case PdfBoxGuidelineStyle.unknown:
        throw ArgumentError.value(value, 'value',
            'The guideline style shall be a name defined by Table 361');
    }
  }

  /// Sets `/S` to an arbitrary name.
  PdfBoxStyle setStyleName(PdfName name) {
    pdfRepresentation().put(style, name);
    return this;
  }

  /// Gets `/S` as written; `null` means the default, solid.
  Future<PdfName?> getStyleName() async =>
      await pdfRepresentation().nameEntry(style);

  /// Gets `/S`; the default is [PdfBoxGuidelineStyle.solid].
  Future<PdfBoxGuidelineStyle> getStyle() async {
    final name = await getStyleName();
    if (name == null) return PdfBoxGuidelineStyle.solid;
    switch (name.getValue()) {
      case 'S':
        return PdfBoxGuidelineStyle.solid;
      case 'D':
        return PdfBoxGuidelineStyle.dashed;
      default:
        return PdfBoxGuidelineStyle.unknown;
    }
  }

  /// Sets `/D`, the dash array of a dashed guideline.
  ///
  /// "The dash phase shall not be specified and shall be assumed to be 0", so
  /// only the array of dashes and gaps is stored.
  PdfBoxStyle setDashArray(List<double> pattern) {
    if (pattern.isEmpty) {
      throw ArgumentError.value(pattern, 'pattern',
          'A box style /D shall list at least one dash length (Table 361)');
    }
    for (final entry in pattern) {
      if (entry < 0) {
        throw ArgumentError.value(pattern, 'pattern',
            'A box style /D entry shall not be negative (8.4.3.6)');
      }
    }
    pdfRepresentation().put(dashArray, PdfArray.fromDoubles(pattern));
    return this;
  }

  /// Gets `/D`; the default is `[3]`.
  Future<List<double>> getDashArray() async =>
      await _numbers(dashArray) ?? defaultDashArray;

  Future<List<double>?> _numbers(PdfName key) async {
    final array = await pdfRepresentation().arrayEntry(key);
    if (array == null) return null;
    final values = <double>[];
    for (var i = 0; i < array.size(); i++) {
      final number = await array.numberEntry(i);
      if (number == null) return null;
      values.add(number.doubleValue());
    }
    return values;
  }
}

/// A box colour information dictionary.
///
/// ISO 32000-1:2008, 14.11.2.2, Table 360: the `/BoxColorInfo` entry of a page
/// object (Table 30), holding one [PdfBoxStyle] per page boundary other than
/// the media box. "If a given entry is absent, the conforming reader shall use
/// its own current default settings instead."
class PdfBoxColorInfo extends PdfObjectWrapper<PdfDictionary> {
  /// `/BoxColorInfo`, the page object entry of Table 30.
  static final PdfName boxColorInfo = PdfName.intern('BoxColorInfo');

  PdfBoxColorInfo(super.pdfObject);

  /// Creates an empty box colour information dictionary.
  PdfBoxColorInfo.create() : super(PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Reads `/BoxColorInfo` from [page], or `null` when the page has none.
  static Future<PdfBoxColorInfo?> ofPage(PdfDictionary page) async {
    final dictionary = await page.dictionaryEntry(boxColorInfo);
    return dictionary == null ? null : PdfBoxColorInfo(dictionary);
  }

  /// Writes this dictionary into the `/BoxColorInfo` entry of [page].
  void attachToPage(PdfDictionary page) {
    page.put(boxColorInfo, pdfRepresentation());
    page.markChanged();
  }

  /// Sets the box style of [box].
  ///
  /// Table 360 has no entry for the media box, so [PdfPageBox.media] is
  /// refused.
  PdfBoxColorInfo setStyleFor(PdfPageBox box, PdfBoxStyle style) {
    pdfRepresentation().put(_key(box), style.pdfRepresentation());
    return this;
  }

  /// Gets the box style of [box]; `null` means the reader's own defaults.
  Future<PdfBoxStyle?> getStyleFor(PdfPageBox box) async {
    final dictionary = await pdfRepresentation().dictionaryEntry(_key(box));
    return dictionary == null ? null : PdfBoxStyle(dictionary);
  }

  /// Removes the box style of [box].
  void removeStyleFor(PdfPageBox box) {
    pdfRepresentation().remove(_key(box));
    markChanged();
  }

  /// The page boundaries Table 360 can describe, in nesting order.
  static const List<PdfPageBox> describableBoxes = [
    PdfPageBox.crop,
    PdfPageBox.bleed,
    PdfPageBox.trim,
    PdfPageBox.art,
  ];

  static PdfName _key(PdfPageBox box) {
    if (box == PdfPageBox.media) {
      throw ArgumentError.value(
          box,
          'box',
          'A box colour information dictionary has no media box entry '
              '(Table 360)');
    }
    return PdfPageBoundaries.keyOf(box);
  }
}
