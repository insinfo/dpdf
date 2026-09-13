import '../../exceptions/pdf_exception.dart';
import '../../geom/rectangle.dart';
import '../pdf_array.dart';
import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';

/// Values of `/F` in a number format dictionary (ISO 32000-1:2008, 12.9,
/// Table 263): how a fractional value is displayed.
enum PdfFractionDisplay {
  /// `/D`, a decimal to the precision given by `/D`. The Table 263 default.
  decimal('D'),

  /// `/F`, a fraction with the denominator given by `/D`.
  fraction('F'),

  /// `/R`, no fractional part, rounded to the nearest whole unit.
  round('R'),

  /// `/T`, no fractional part, truncated to whole units.
  truncate('T');

  const PdfFractionDisplay(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// The value as a PDF name object.
  PdfName toPdfName() => PdfName.intern(pdfName);

  /// Resolves an `/F` value, or `null` when unrecognized.
  static PdfFractionDisplay? fromPdfName(PdfName? name) {
    if (name == null) return null;
    final value = name.getValue();
    for (final candidate in values) {
      if (candidate.pdfName == value) return candidate;
    }
    return null;
  }
}

/// Values of `/O` in a number format dictionary (Table 263): where the unit
/// label sits with respect to the value.
enum PdfLabelPosition {
  /// `/S`, the label is a suffix. The Table 263 default.
  suffix('S'),

  /// `/P`, the label is a prefix.
  prefix('P');

  const PdfLabelPosition(this.pdfName);

  /// The name written to the PDF file.
  final String pdfName;

  /// The value as a PDF name object.
  PdfName toPdfName() => PdfName.intern(pdfName);

  /// Resolves an `/O` value, or `null` when unrecognized.
  static PdfLabelPosition? fromPdfName(PdfName? name) {
    if (name == null) return null;
    final value = name.getValue();
    for (final candidate in values) {
      if (candidate.pdfName == value) return candidate;
    }
    return null;
  }
}

/// A number format dictionary of ISO 32000-1:2008, 12.9, Table 263.
///
/// It represents one unit of measurement, saying how the unit is labelled and
/// by which factor a value in the units of the previous array element is
/// multiplied to obtain a value in this one.
class PdfNumberFormat extends PdfObjectWrapper<PdfDictionary> {
  /// The `/Type` value of a number format dictionary.
  static final PdfName numberFormat = PdfName.intern('NumberFormat');

  /// `/U`, the unit label.
  static final PdfName unitLabel = PdfName.intern('U');

  /// `/C`, the conversion factor.
  static final PdfName conversionFactor = PdfName.intern('C');

  /// `/F`, how a fractional value is displayed.
  static final PdfName fractionDisplay = PdfName.intern('F');

  /// `/D`, the precision or the denominator of a fractional amount.
  static final PdfName precision = PdfName.intern('D');

  /// `/FD`, whether a fraction keeps its denominator and low-order zeros.
  static final PdfName fixedDenominator = PdfName.intern('FD');

  /// `/RT`, the text between orders of thousands.
  static final PdfName thousandsSeparator = PdfName.intern('RT');

  /// `/RD`, the text used as the decimal position.
  static final PdfName decimalSeparator = PdfName.intern('RD');

  /// `/PS`, the text concatenated to the left of the label.
  static final PdfName labelPrefix = PdfName.intern('PS');

  /// `/SS`, the text concatenated after the label.
  static final PdfName labelSuffix = PdfName.intern('SS');

  /// `/O`, the position of the label with respect to the value.
  static final PdfName labelPosition = PdfName.intern('O');

  /// Wraps an existing number format dictionary.
  PdfNumberFormat(super.pdfObject);

  /// Creates a number format with the two entries Table 263 requires: the unit
  /// label `/U` and the conversion factor `/C`.
  PdfNumberFormat.create(String unit, double factor) : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, numberFormat);
    setUnit(unit);
    setConversionFactor(factor);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/U`, the label displaying this unit. Table 263 requires it, so an
  /// empty label is rejected.
  PdfNumberFormat setUnit(String unit) {
    if (unit.isEmpty) {
      throw PdfException('/U is the required unit label and cannot be empty.');
    }
    pdfRepresentation().put(unitLabel, PdfString(unit));
    markChanged();
    return this;
  }

  /// Gets `/U`, or `null` when the required entry is missing.
  Future<String?> getUnit() async {
    return (await pdfRepresentation().stringEntry(unitLabel))
        ?.decodeMappingText();
  }

  /// Sets `/C`, the factor multiplying a value in partial units of the previous
  /// array element. A factor of zero would collapse every measurement, so it is
  /// rejected along with negative factors.
  PdfNumberFormat setConversionFactor(double factor) {
    if (!(factor > 0)) {
      throw PdfException(
          '/C is a conversion factor and shall be positive, got $factor.');
    }
    pdfRepresentation().put(conversionFactor, PdfNumber(factor));
    markChanged();
    return this;
  }

  /// Gets `/C`, or `null` when the required entry is missing.
  Future<double?> getConversionFactor() async {
    return (await pdfRepresentation().numberEntry(conversionFactor))
        ?.doubleValue();
  }

  /// Sets `/F`, meaningful only for the last dictionary of a number format
  /// array. Default [PdfFractionDisplay.decimal].
  PdfNumberFormat setFractionDisplay(PdfFractionDisplay display) {
    pdfRepresentation().put(fractionDisplay, display.toPdfName());
    markChanged();
    return this;
  }

  /// Gets `/F`, defaulting to [PdfFractionDisplay.decimal].
  Future<PdfFractionDisplay> getFractionDisplay() async {
    return PdfFractionDisplay.fromPdfName(
            await pdfRepresentation().nameEntry(fractionDisplay)) ??
        PdfFractionDisplay.decimal;
  }

  /// Sets `/D`, the precision of a decimal display or the denominator of a
  /// fractional one.
  ///
  /// Table 263 requires a positive integer, and a multiple of 10 when `/F` is
  /// `/D`, so the value is checked against the `/F` currently stored.
  Future<PdfNumberFormat> setPrecision(int value) async {
    if (value <= 0) {
      throw PdfException('/D shall be a positive integer, got $value.');
    }
    final display = await getFractionDisplay();
    if (display == PdfFractionDisplay.decimal && value % 10 != 0) {
      throw PdfException(
          '/D is the precision of a decimal display and shall be a multiple '
          'of 10, got $value.');
    }
    pdfRepresentation().put(precision, PdfNumber.fromInt(value));
    markChanged();
    return this;
  }

  /// Gets `/D`, or the Table 263 default for the current `/F`: 100 for a
  /// decimal display, 16 for a fractional one.
  Future<int> getPrecision() async {
    final stored = await pdfRepresentation().numberEntry(precision);
    if (stored != null) return stored.intValue();
    return await getFractionDisplay() == PdfFractionDisplay.fraction ? 16 : 100;
  }

  /// Sets `/FD`: a fraction keeps its denominator and its low-order zeros.
  /// Default `false`.
  PdfNumberFormat setFixedDenominator(bool value) {
    pdfRepresentation().put(fixedDenominator, PdfBoolean(value));
    markChanged();
    return this;
  }

  /// Gets `/FD`, defaulting to `false`.
  Future<bool> getFixedDenominator() async {
    return (await pdfRepresentation().booleanEntry(fixedDenominator))
            ?.getValue() ??
        false;
  }

  /// Sets `/RT`, the text between orders of thousands. An empty string means
  /// no text is added; Table 263 defaults to a comma.
  PdfNumberFormat setThousandsSeparator(String text) =>
      _putText(thousandsSeparator, text);

  /// Gets `/RT`, defaulting to the Table 263 comma.
  Future<String> getThousandsSeparator() => _text(thousandsSeparator, ',');

  /// Sets `/RD`, the text used as the decimal position. Table 263 defaults to
  /// a period.
  PdfNumberFormat setDecimalSeparator(String text) =>
      _putText(decimalSeparator, text);

  /// Gets `/RD`, defaulting to the Table 263 period.
  Future<String> getDecimalSeparator() => _text(decimalSeparator, '.');

  /// Sets `/PS`, the text concatenated to the left of the label. Table 263
  /// defaults to a single space.
  PdfNumberFormat setLabelPrefix(String text) => _putText(labelPrefix, text);

  /// Gets `/PS`, defaulting to the Table 263 single space.
  Future<String> getLabelPrefix() => _text(labelPrefix, ' ');

  /// Sets `/SS`, the text concatenated after the label. Table 263 defaults to
  /// a single space.
  PdfNumberFormat setLabelSuffix(String text) => _putText(labelSuffix, text);

  /// Gets `/SS`, defaulting to the Table 263 single space.
  Future<String> getLabelSuffix() => _text(labelSuffix, ' ');

  /// Sets `/O`, the position of the label. Default [PdfLabelPosition.suffix].
  PdfNumberFormat setLabelPosition(PdfLabelPosition position) {
    pdfRepresentation().put(labelPosition, position.toPdfName());
    markChanged();
    return this;
  }

  /// Gets `/O`, defaulting to [PdfLabelPosition.suffix].
  Future<PdfLabelPosition> getLabelPosition() async {
    return PdfLabelPosition.fromPdfName(
            await pdfRepresentation().nameEntry(labelPosition)) ??
        PdfLabelPosition.suffix;
  }

  /// Checks the two entries Table 263 requires.
  Future<void> validate() async {
    if (await getUnit() == null) {
      throw PdfException('Table 263 requires /U, the unit label.');
    }
    if (await getConversionFactor() == null) {
      throw PdfException('Table 263 requires /C, the conversion factor.');
    }
  }

  PdfNumberFormat _putText(PdfName key, String text) {
    pdfRepresentation().put(key, PdfString(text));
    markChanged();
    return this;
  }

  Future<String> _text(PdfName key, String fallback) async {
    return (await pdfRepresentation().stringEntry(key))?.decodeMappingText() ??
        fallback;
  }
}

/// A measure dictionary of ISO 32000-1:2008, 12.9, Tables 261 and 262.
///
/// It describes the alternate coordinate system of a region of a page, so a
/// reader can turn page coordinates into real-world measurements. PDF 1.6
/// defines a single `/Subtype`, `/RL`, a rectilinear coordinate system, whose
/// additional entries Table 262 lists.
class PdfMeasure extends PdfObjectWrapper<PdfDictionary> {
  /// The `/Type` value of a measure dictionary.
  static final PdfName measure = PdfName.intern('Measure');

  /// `/Subtype`.
  static final PdfName subtype = PdfName.intern('Subtype');

  /// `/RL`, the rectilinear coordinate system and the Table 261 default.
  static final PdfName rectilinear = PdfName.intern('RL');

  /// `/R`, the scale ratio of the drawing.
  static final PdfName scaleRatio = PdfName.intern('R');

  /// `/X`, the number format array for change along the x axis.
  static final PdfName xAxis = PdfName.intern('X');

  /// `/Y`, the number format array for change along the y axis.
  static final PdfName yAxis = PdfName.intern('Y');

  /// `/D`, the number format array for distance in any direction.
  static final PdfName distance = PdfName.intern('D');

  /// `/A`, the number format array for area.
  static final PdfName area = PdfName.intern('A');

  /// `/T`, the number format array for angles.
  static final PdfName angle = PdfName.intern('T');

  /// `/S`, the number format array for the slope of a line.
  static final PdfName slope = PdfName.intern('S');

  /// `/O`, the origin of the measuring coordinate system.
  static final PdfName origin = PdfName.intern('O');

  /// `/CYX`, the factor converting the largest y units to the largest x units.
  static final PdfName cyx = PdfName.intern('CYX');

  /// Wraps an existing measure dictionary.
  PdfMeasure(super.pdfObject);

  /// Creates a rectilinear measure dictionary, with `/Type /Measure` and
  /// `/Subtype /RL`.
  PdfMeasure.createRectilinear() : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, measure);
    pdfRepresentation().put(subtype, rectilinear);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/Subtype`, defaulting to `/RL` as Table 261 prescribes.
  Future<PdfName> getSubtype() async {
    return await pdfRepresentation().nameEntry(subtype) ?? rectilinear;
  }

  /// Sets `/R`, the scale ratio of the drawing, such as `1/4 in = 1 ft`.
  /// Table 262 requires it, so an empty ratio is rejected.
  PdfMeasure setScaleRatio(String ratio) {
    if (ratio.isEmpty) {
      throw PdfException('/R is the required scale ratio and cannot be empty.');
    }
    pdfRepresentation().put(scaleRatio, PdfString(ratio));
    markChanged();
    return this;
  }

  /// Gets `/R`, or `null` when the required entry is missing.
  Future<String?> getScaleRatio() async {
    return (await pdfRepresentation().stringEntry(scaleRatio))
        ?.decodeMappingText();
  }

  /// Sets one of the number format arrays of Table 262. The array is written in
  /// descending order of granularity, so its first element carries the scale
  /// factor for the largest unit.
  PdfMeasure setNumberFormats(PdfName key, List<PdfNumberFormat> formats) {
    if (formats.isEmpty) {
      throw PdfException(
          'A number format array shall contain one or more number format '
          'dictionaries, so /${key.getValue()} cannot be empty.');
    }
    final array = PdfArray();
    for (final format in formats) {
      array.add(format.pdfRepresentation());
    }
    pdfRepresentation().put(key, array);
    markChanged();
    return this;
  }

  /// Gets one of the number format arrays of Table 262, in array order, or an
  /// empty list when the entry is absent.
  Future<List<PdfNumberFormat>> getNumberFormats(PdfName key) async {
    final array = await pdfRepresentation().arrayEntry(key);
    if (array == null) return const [];
    final result = <PdfNumberFormat>[];
    for (var index = 0; index < array.size(); index++) {
      final entry = await array.dictionaryEntry(index);
      if (entry != null) result.add(PdfNumberFormat(entry));
    }
    return result;
  }

  /// Sets `/O`, the origin of the measuring coordinate system in default user
  /// space. Table 262 defines it as an array of exactly two numbers.
  PdfMeasure setOrigin(double x, double y) {
    pdfRepresentation().put(origin, PdfArray.fromDoubles([x, y]));
    markChanged();
    return this;
  }

  /// Gets `/O` as `[x, y]`, or `null` when absent. Table 262 then places the
  /// origin at the lower-left corner of the viewport's `/BBox`.
  Future<List<double>?> getOrigin() async {
    final array = await pdfRepresentation().arrayEntry(origin);
    if (array == null) return null;
    return await array.toDoubleArray();
  }

  /// Sets `/CYX`, converting the largest y units to the largest x units.
  /// Table 262 says it is meaningful only when `/Y` is present.
  PdfMeasure setCyx(double factor) {
    pdfRepresentation().put(cyx, PdfNumber(factor));
    markChanged();
    return this;
  }

  /// Gets `/CYX`, or `null` when absent. Without it, the calculations that
  /// need equivalent units cannot be performed.
  Future<double?> getCyx() async {
    return (await pdfRepresentation().numberEntry(cyx))?.doubleValue();
  }

  /// Checks a rectilinear measure dictionary against Table 262: `/R`, `/X`,
  /// `/D` and `/A` are required, every number format array shall be non empty
  /// and hold valid number format dictionaries, and `/O` shall hold exactly two
  /// numbers.
  Future<void> validate() async {
    if (await getSubtype() != rectilinear) {
      // Table 262 describes the entries of the rectilinear subtype only.
      return;
    }
    if (await getScaleRatio() == null) {
      throw PdfException('Table 262 requires /R, the scale ratio.');
    }
    for (final key in [xAxis, distance, area]) {
      if (!pdfRepresentation().containsKey(key)) {
        throw PdfException(
            'Table 262 requires /${key.getValue()}, a number format array.');
      }
    }
    for (final key in [xAxis, yAxis, distance, area, angle, slope]) {
      if (!pdfRepresentation().containsKey(key)) continue;
      final formats = await getNumberFormats(key);
      if (formats.isEmpty) {
        throw PdfException(
            '/${key.getValue()} shall contain one or more number format '
            'dictionaries.');
      }
      for (final format in formats) {
        await format.validate();
      }
    }
    final start = await getOrigin();
    if (start != null && start.length != 2) {
      throw PdfException(
          '/O shall be an array of two numbers, got ${start.length}.');
    }
  }
}

/// A viewport dictionary of ISO 32000-1:2008, 12.9, Table 260.
///
/// A viewport is a rectangular region of a page that carries its own
/// measurement scale. The `/VP` entry of a page object holds the viewports in
/// drawing order.
class PdfViewport extends PdfObjectWrapper<PdfDictionary> {
  /// The `/Type` value of a viewport dictionary.
  static final PdfName viewport = PdfName.intern('Viewport');

  /// `/VP`, the page entry holding the array of viewports.
  static final PdfName viewportsKey = PdfName.intern('VP');

  /// `/BBox`, the location of the viewport on the page.
  static final PdfName bbox = PdfName.intern('BBox');

  /// `/Name`, a descriptive title of the viewport.
  static final PdfName name = PdfName.intern('Name');

  /// `/Measure`, the scale and units applying inside the viewport.
  static final PdfName measureKey = PdfName.intern('Measure');

  /// `/PtData`, a point data dictionary. It is not part of ISO 32000-1:2008
  /// and is carried through unchanged for documents that use it.
  static final PdfName pointData = PdfName.intern('PtData');

  /// Wraps an existing viewport dictionary.
  PdfViewport(super.pdfObject);

  /// Creates a viewport covering [bounds], with `/Type /Viewport` and the
  /// required `/BBox`. Table 260 wants the rectangle normalized, lower-left
  /// corner followed by upper-right, which is how a [Rectangle] is written.
  PdfViewport.create(Rectangle bounds) : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, viewport);
    setBounds(bounds);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/BBox`, which Table 260 requires. A rectangle with no area could
  /// never contain a point, so it is rejected.
  PdfViewport setBounds(Rectangle bounds) {
    if (bounds.getWidth() <= 0 || bounds.getHeight() <= 0) {
      throw PdfException(
          '/BBox shall be a normalized rectangle with a positive width and '
          'height, got ${bounds.getWidth()} by ${bounds.getHeight()}.');
    }
    pdfRepresentation().put(bbox, bounds.toPdfArray());
    markChanged();
    return this;
  }

  /// Gets `/BBox`, or `null` when the required entry is missing or malformed.
  Future<Rectangle?> getBounds() async {
    final array = await pdfRepresentation().arrayEntry(bbox);
    if (array == null || array.size() != 4) return null;
    return await Rectangle.fromPdfArray(array);
  }

  /// Sets `/Name`, the title of the viewport shown in a user interface.
  PdfViewport setName(String title) {
    pdfRepresentation().put(name, PdfString(title));
    markChanged();
    return this;
  }

  /// Gets `/Name`, or `null` when absent.
  Future<String?> getName() async {
    return (await pdfRepresentation().stringEntry(name))?.decodeMappingText();
  }

  /// Sets `/Measure`, the measure dictionary applying inside this viewport.
  PdfViewport setMeasure(PdfMeasure measure) {
    pdfRepresentation().put(measureKey, measure.pdfRepresentation());
    markChanged();
    return this;
  }

  /// Gets `/Measure`, or `null` when the viewport carries no scale.
  Future<PdfMeasure?> getMeasure() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(measureKey);
    return dictionary == null ? null : PdfMeasure(dictionary);
  }

  /// Sets `/PtData`, carried through for documents that use the point data
  /// dictionary of later specifications.
  PdfViewport setPointData(PdfObject data) {
    pdfRepresentation().put(pointData, data);
    markChanged();
    return this;
  }

  /// Gets `/PtData`, resolved through any indirect reference, or `null`.
  Future<PdfObject?> getPointData() => pdfRepresentation().get(pointData, true);

  /// Whether the point `(x, y)` in default user space falls inside `/BBox`.
  Future<bool> contains(double x, double y) async {
    final bounds = await getBounds();
    if (bounds == null) return false;
    return x >= bounds.getLeft() &&
        x <= bounds.getRight() &&
        y >= bounds.getBottom() &&
        y <= bounds.getTop();
  }

  /// Checks the viewport against Table 260: `/BBox` is required, and any
  /// `/Measure` shall itself be valid.
  Future<void> validate() async {
    if (await getBounds() == null) {
      throw PdfException(
          'Table 260 requires /BBox, a rectangle of four numbers.');
    }
    await (await getMeasure())?.validate();
  }
}
