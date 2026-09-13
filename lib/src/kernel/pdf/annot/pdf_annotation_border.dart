import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';

/// Border style dictionary.
///
/// See ISO 32000-1:2008, 12.5.4 "Border Styles", Table 166.
class PdfBorderStyle extends PdfObjectWrapper<PdfDictionary> {
  /// A solid rectangle surrounding the annotation.
  static final PdfName solid = PdfName.intern('S');

  /// A dashed rectangle surrounding the annotation.
  static final PdfName dashed = PdfName.intern('D');

  /// A simulated embossed rectangle.
  static final PdfName beveled = PdfName.intern('B');

  /// A simulated engraved rectangle.
  static final PdfName inset = PdfName.intern('I');

  /// A single line along the bottom of the annotation rectangle.
  static final PdfName underline = PdfName.intern('U');

  PdfBorderStyle(super.pdfObject);

  /// Creates an empty border style dictionary with `/Type /Border`.
  PdfBorderStyle.create() : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, PdfName.border);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Sets the border width in points. A width of 0 means no border (Table 166).
  PdfBorderStyle setWidth(double width) {
    pdfRepresentation().put(PdfName.w, PdfNumber(width));
    return this;
  }

  /// Gets the border width, defaulting to 1 as specified in Table 166.
  Future<double> getWidth() async {
    return (await pdfRepresentation().numberEntry(PdfName.w))?.getValue() ??
        1.0;
  }

  /// Sets the border style name (one of [solid], [dashed], [beveled],
  /// [inset] or [underline]).
  PdfBorderStyle setStyle(PdfName style) {
    pdfRepresentation().put(PdfName.s, style);
    return this;
  }

  /// Gets the border style name. Unknown names are reported as written; the
  /// caller decides to fall back to the default as required by Table 166.
  Future<PdfName?> getStyle() async {
    return await pdfRepresentation().nameEntry(PdfName.s);
  }

  /// Sets the dash array used when the style is [dashed]. Default `[3]`.
  PdfBorderStyle setDashPattern(List<double> dashes) {
    pdfRepresentation().put(PdfName.d, PdfArray.fromDoubles(dashes));
    return this;
  }

  /// Gets the dash array. Returns `[3]` when absent, per Table 166.
  Future<List<double>> getDashPattern() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.d);
    if (array == null) return const [3.0];
    return await array.toDoubleArray();
  }
}

/// Border effect dictionary.
///
/// See ISO 32000-1:2008, 12.5.4 "Border Styles", Table 167.
class PdfBorderEffect extends PdfObjectWrapper<PdfDictionary> {
  /// No effect; the border is described by the annotation's `/BS` entry.
  static final PdfName noEffect = PdfName.intern('S');

  /// The border should appear "cloudy".
  static final PdfName cloudy = PdfName.intern('C');

  PdfBorderEffect(super.pdfObject);

  PdfBorderEffect.create() : super(PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Sets the effect name, [noEffect] or [cloudy].
  PdfBorderEffect setEffect(PdfName effect) {
    pdfRepresentation().put(PdfName.s, effect);
    return this;
  }

  /// Gets the effect name; the default is [noEffect] (Table 167).
  Future<PdfName> getEffect() async {
    return await pdfRepresentation().nameEntry(PdfName.s) ?? noEffect;
  }

  /// Sets the cloud intensity, valid only when the effect is [cloudy].
  /// The value shall lie in the range 0 to 2 (Table 167).
  PdfBorderEffect setIntensity(double intensity) {
    if (intensity < 0 || intensity > 2) {
      throw ArgumentError.value(
          intensity, 'intensity', 'Border effect intensity must be in [0, 2]');
    }
    pdfRepresentation().put(PdfName.i, PdfNumber(intensity));
    return this;
  }

  /// Gets the cloud intensity; the default is 0 (Table 167).
  Future<double> getIntensity() async {
    return (await pdfRepresentation().numberEntry(PdfName.i))?.getValue() ??
        0.0;
  }
}

/// Line ending styles usable by line, polyline and free text callout
/// annotations.
///
/// See ISO 32000-1:2008, Table 176 "Line ending styles".
abstract final class PdfLineEnding {
  static final PdfName square = PdfName.intern('Square');
  static final PdfName circle = PdfName.intern('Circle');
  static final PdfName diamond = PdfName.intern('Diamond');
  static final PdfName openArrow = PdfName.intern('OpenArrow');
  static final PdfName closedArrow = PdfName.intern('ClosedArrow');
  static final PdfName none = PdfName.intern('None');
  static final PdfName butt = PdfName.intern('Butt');
  static final PdfName rOpenArrow = PdfName.intern('ROpenArrow');
  static final PdfName rClosedArrow = PdfName.intern('RClosedArrow');
  static final PdfName slash = PdfName.intern('Slash');

  /// Every style named in Table 176.
  static final Set<String> all = {
    square.getValue(),
    circle.getValue(),
    diamond.getValue(),
    openArrow.getValue(),
    closedArrow.getValue(),
    none.getValue(),
    butt.getValue(),
    rOpenArrow.getValue(),
    rClosedArrow.getValue(),
    slash.getValue(),
  };
}

/// Helpers shared by the annotation entries that carry colour arrays whose
/// length selects the colour space (Table 164 `/C`, Table 175/177/178 `/IC`).
abstract final class PdfAnnotationColor {
  /// Validates the component count defined by Table 164: 0 (transparent),
  /// 1 (DeviceGray), 3 (DeviceRGB) or 4 (DeviceCMYK).
  static PdfArray toArray(List<double> components) {
    if (components.isNotEmpty &&
        components.length != 1 &&
        components.length != 3 &&
        components.length != 4) {
      throw ArgumentError.value(components, 'components',
          'Annotation colour must have 0, 1, 3 or 4 components');
    }
    for (final component in components) {
      if (component < 0 || component > 1) {
        throw ArgumentError.value(components, 'components',
            'Annotation colour components must lie in [0, 1]');
      }
    }
    return PdfArray.fromDoubles(components);
  }

  /// Reads a colour array, returning null when the entry is absent.
  static Future<List<double>?> fromEntry(
      PdfDictionary dictionary, PdfName key) async {
    final array = await dictionary.arrayEntry(key);
    if (array == null) return null;
    return await array.toDoubleArray();
  }
}

/// Converts a quadrilateral list into the flat `8 x n` `/QuadPoints` array
/// described in Table 179.
PdfArray buildQuadPoints(List<double> coordinates) {
  if (coordinates.isEmpty || coordinates.length % 8 != 0) {
    throw ArgumentError.value(coordinates, 'coordinates',
        'QuadPoints must contain 8 x n numbers (Table 179)');
  }
  return PdfArray.fromDoubles(coordinates);
}

/// Reads a numeric array entry into plain doubles, or null when absent.
Future<List<double>?> readNumberArray(
    PdfDictionary dictionary, PdfName key) async {
  final array = await dictionary.arrayEntry(key);
  if (array == null) return null;
  return await array.toDoubleArray();
}

/// Reads an array of names, or null when absent.
Future<List<PdfName>?> readNameArray(
    PdfDictionary dictionary, PdfName key) async {
  final array = await dictionary.arrayEntry(key);
  if (array == null) return null;
  final names = <PdfName>[];
  for (var i = 0; i < array.size(); i++) {
    final value = await array.get(i);
    if (value is PdfName) names.add(value);
  }
  return names;
}

/// Reads an array of arrays of numbers, used by `/InkList` (Table 182) and
/// `/RF` related file arrays.
Future<List<List<double>>?> readNumberMatrix(
    PdfDictionary dictionary, PdfName key) async {
  final array = await dictionary.arrayEntry(key);
  if (array == null) return null;
  final result = <List<double>>[];
  for (var i = 0; i < array.size(); i++) {
    final row = await array.get(i);
    if (row is PdfArray) result.add(await row.toDoubleArray());
  }
  return result;
}

/// Builds an array of number arrays.
PdfArray buildNumberMatrix(List<List<double>> rows) {
  final array = PdfArray();
  for (final row in rows) {
    array.add(PdfArray.fromDoubles(row));
  }
  return array;
}

/// Builds a `/RD` rectangle-difference array (Tables 174, 177, 180).
/// Each value shall be greater than or equal to 0.
PdfArray buildRectangleDifferences(
    double left, double top, double right, double bottom) {
  for (final value in [left, top, right, bottom]) {
    if (value < 0) {
      throw ArgumentError.value(
          value, 'differences', 'Rectangle differences shall not be negative');
    }
  }
  return PdfArray.fromDoubles([left, top, right, bottom]);
}

/// Convenience for putting an optional object entry only when non-null.
void putIfPresent(PdfDictionary dictionary, PdfName key, PdfObject? value) {
  if (value != null) dictionary.put(key, value);
}
