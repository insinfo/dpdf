import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_color_space.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function.dart';

/// Abstract class for special color spaces (Pattern, Indexed, Separation, DeviceN).
abstract class PdfSpecialCs extends PdfColorSpace {
  PdfSpecialCs(super.pdfObject);

  @override
  bool requiresIndirectStorage() => false;
}

/// Represents a Pattern color space.
class PdfSpecialCsPattern extends PdfSpecialCs {
  /// For the `[/Pattern base]` (uncoloured) form, the space the pattern's own
  /// colour operands are given in; null for the plain `/Pattern` form.
  final PdfColorSpace? underlyingColorSpace;

  /// Creates a new [PdfSpecialCsPattern] object.
  PdfSpecialCsPattern()
      : underlyingColorSpace = null,
        super(PdfName.pattern);

  /// Creates the `[/Pattern base]` form, whose operands are colours of [base].
  PdfSpecialCsPattern.withBase(
      PdfArray super.pdfObject, this.underlyingColorSpace);

  @override
  int getNumberOfComponents() {
    // This is hard to determine without more context (tiling vs shading, uncolored vs colored)
    // For specific instances we might know.
    // Kept as -1, the documented "unknown" answer: a coloured pattern takes no
    // operands at all while an uncoloured one takes as many as its underlying
    // space, so no single number is right for the family.
    return -1;
  }

  /// Always throws.
  ///
  /// A pattern is a painting procedure, not a colour: its appearance comes
  /// from a content stream or a shading, so a caller must render it rather
  /// than convert it. This throws instead of returning null so that a
  /// rasterizer cannot silently paint the wrong thing.
  @override
  List<double> toRgb(List<double> components) {
    throw UnsupportedError(
        'A /Pattern colour space has no colour of its own; render the pattern '
        'instead of converting it.');
  }
}

/// Represents an Indexed color space (ISO 32000-1, clause 8.6.6.3).
///
/// `[/Indexed base hival lookup]`: a single component selects an entry of a
/// palette of colours in [base].
class PdfSpecialCsIndexed extends PdfSpecialCs {
  /// The colour space the palette entries are expressed in.
  final PdfColorSpace base;

  /// Highest valid index; the palette holds `hival + 1` entries.
  final int hival;

  /// Palette bytes: `hival + 1` groups of `base.getNumberOfComponents()`.
  final Uint8List lookup;

  PdfSpecialCsIndexed(
      PdfArray super.pdfObject, this.base, this.hival, this.lookup);

  /// Builds an Indexed space from its array form; returns null if the base
  /// space or the palette cannot be resolved.
  static Future<PdfSpecialCsIndexed?> parseArray(PdfArray array) async {
    if (array.size() < 4) return null;
    final base = await PdfColorSpace.makeColorSpace(await array.get(1));
    if (base == null || base.getNumberOfComponents() < 1) return null;
    final hival = (await array.numberEntry(2))?.intValue();
    if (hival == null || hival < 0) return null;

    // The palette is a string in a direct definition and a stream when it is
    // large enough to be worth compressing.
    final lookupObject = await array.get(3);
    Uint8List? lookup;
    if (lookupObject is PdfStream) {
      lookup = await lookupObject.getBytes();
    } else if (lookupObject is PdfString) {
      lookup = lookupObject.getValueBytes();
    }
    if (lookup == null) return null;

    return PdfSpecialCsIndexed(array, base, hival, lookup);
  }

  @override
  int getNumberOfComponents() => 1;

  @override
  List<double> getComponentRange(int index) => <double>[0.0, hival.toDouble()];

  @override
  List<double> toRgb(List<double> components) {
    final raw = PdfColorSpace.componentAt(components, 0);
    var index = raw.isNaN ? 0 : raw.round();
    if (index < 0) index = 0;
    if (index > hival) index = hival;

    final n = base.getNumberOfComponents();
    final baseComponents = List<double>.filled(n, 0.0);
    for (var j = 0; j < n; j++) {
      final offset = index * n + j;
      final byte = offset < lookup.length ? lookup[offset] : 0;
      // Palette bytes are always 0..255 whatever the base space is, so they
      // have to be spread over that component's own range (0..1 for the device
      // spaces, 0..100 and /Range for Lab).
      final componentRange = base.getComponentRange(j);
      baseComponents[j] = componentRange[0] +
          byte * (componentRange[1] - componentRange[0]) / 255.0;
    }
    return base.toRgb(baseComponents);
  }
}

/// Represents a Separation color space (ISO 32000-1, clause 8.6.6.4).
///
/// `[/Separation name alternate tintTransform]`: one tint value is mapped by
/// the tint transform into a colour of the alternate space.
class PdfSpecialCsSeparation extends PdfSpecialCs {
  /// The colourant name; `/None` marks a separation that paints nothing.
  final PdfName colorantName;

  final PdfColorSpace alternate;

  final PdfFunction tintTransform;

  PdfSpecialCsSeparation(PdfArray super.pdfObject, this.colorantName,
      this.alternate, this.tintTransform);

  /// The special colourant name `/All` of clause 8.6.6.4.
  static final PdfName allColorant = PdfName.intern('All');

  static Future<PdfSpecialCsSeparation?> parseArray(PdfArray array) async {
    if (array.size() < 4) return null;
    final name = await array.nameEntry(1);
    final alternate = await PdfColorSpace.makeColorSpace(await array.get(2));
    final tint = await PdfFunction.parse(await array.get(3));
    if (name == null || alternate == null || tint == null) return null;
    return PdfSpecialCsSeparation(array, name, alternate, tint);
  }

  /// Whether this is the `/None` separation, which never marks the page.
  bool isNone() => colorantName == PdfName.none;

  /// Whether this is the `/All` separation, which paints every colorant.
  bool isAll() => colorantName == allColorant;

  @override
  int getNumberOfComponents() => 1;

  @override
  List<double> toRgb(List<double> components) {
    // A /None separation is never painted at all. There is no "no paint" value
    // in RGB, so report white, which is what leaving the area untouched looks
    // like on a blank page.
    if (isNone()) {
      return <double>[1.0, 1.0, 1.0];
    }
    final tint =
        PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 0));
    if (isAll()) {
      // Clause 8.6.6.4 requires every reader to support /All and to ignore the
      // alternate space and the tint transform for it: the tint goes to all
      // colorants at once. Every colorant at the same subtractive tint is a
      // neutral, so on an RGB device the honest approximation is 1 - tint.
      final grey = PdfColorSpace.clampUnit(1.0 - tint);
      return <double>[grey, grey, grey];
    }
    return alternate.toRgb(tintTransform.evaluate(<double>[tint]));
  }
}

/// The attributes dictionary of a DeviceN colour space (ISO 32000-1,
/// clause 8.6.6.5, table 71).
///
/// A `/Subtype` of `/NChannel` (PDF 1.6) promises that the dictionary carries
/// enough information — `/Colorants` for the spot components and `/Process`
/// for the process ones — for a reader to blend the components itself instead
/// of going through the tint transform.
class PdfDeviceNAttributes {
  static final PdfName subtypeKey = PdfName.intern('Subtype');
  static final PdfName colorantsKey = PdfName.intern('Colorants');
  static final PdfName processKey = PdfName.intern('Process');
  static final PdfName componentsKey = PdfName.intern('Components');
  static final PdfName mixingHintsKey = PdfName.intern('MixingHints');

  /// `/DeviceN` (the default) or `/NChannel`.
  final PdfName subtype;

  /// `/Colorants`: one Separation space per named spot colourant.
  final Map<String, PdfSpecialCsSeparation> colorants;

  /// The `/Process` `/ColorSpace` entry, or null when there is none.
  final PdfColorSpace? processColorSpace;

  /// The `/Process` `/Components` entry: the names of the process components
  /// in the order the process space expects them.
  final List<PdfName> processComponents;

  /// The `/MixingHints` dictionary, kept verbatim for callers that want it.
  final PdfDictionary? mixingHints;

  PdfDeviceNAttributes(this.subtype, this.colorants, this.processColorSpace,
      this.processComponents, this.mixingHints);

  /// Whether this space asked to be treated as an NChannel space.
  bool isNChannel() => subtype == PdfName.intern('NChannel');

  static Future<PdfDeviceNAttributes> parse(PdfDictionary dict) async {
    final subtype =
        await dict.nameEntry(subtypeKey) ?? PdfName.intern('DeviceN');

    final colorants = <String, PdfSpecialCsSeparation>{};
    final colorantsDict = await dict.dictionaryEntry(colorantsKey);
    if (colorantsDict != null) {
      for (final key in colorantsDict.keySet()) {
        final space =
            await PdfColorSpace.makeColorSpace(await colorantsDict.get(key));
        if (space is PdfSpecialCsSeparation) {
          colorants[key.getValue()] = space;
        }
      }
    }

    PdfColorSpace? processSpace;
    final processComponents = <PdfName>[];
    final processDict = await dict.dictionaryEntry(processKey);
    if (processDict != null) {
      processSpace = await PdfColorSpace.makeColorSpace(
          await processDict.get(PdfName.colorSpace));
      final componentsArray = await processDict.arrayEntry(componentsKey);
      if (componentsArray != null) {
        for (var i = 0; i < componentsArray.size(); i++) {
          final name = await componentsArray.nameEntry(i);
          if (name != null) processComponents.add(name);
        }
      }
    }

    return PdfDeviceNAttributes(subtype, colorants, processSpace,
        processComponents, await dict.dictionaryEntry(mixingHintsKey));
  }
}

/// Represents a DeviceN color space (ISO 32000-1, clause 8.6.6.5).
///
/// `[/DeviceN names alternate tintTransform attributes]`: the same idea as
/// Separation with one tint per colourant name.
class PdfSpecialCsDeviceN extends PdfSpecialCs {
  final List<PdfName> colorantNames;

  final PdfColorSpace alternate;

  final PdfFunction tintTransform;

  /// The optional attributes dictionary (table 71), or null when absent.
  final PdfDeviceNAttributes? attributes;

  PdfSpecialCsDeviceN(PdfArray super.pdfObject, this.colorantNames,
      this.alternate, this.tintTransform,
      [this.attributes]);

  static Future<PdfSpecialCsDeviceN?> parseArray(PdfArray array) async {
    if (array.size() < 4) return null;
    final namesArray = await array.arrayEntry(1);
    final alternate = await PdfColorSpace.makeColorSpace(await array.get(2));
    final tint = await PdfFunction.parse(await array.get(3));
    if (namesArray == null || alternate == null || tint == null) return null;

    final names = <PdfName>[];
    for (var i = 0; i < namesArray.size(); i++) {
      final name = await namesArray.nameEntry(i);
      if (name == null) return null;
      names.add(name);
    }
    if (names.isEmpty) return null;

    PdfDeviceNAttributes? attributes;
    if (array.size() >= 5) {
      final dict = await array.dictionaryEntry(4);
      if (dict != null) attributes = await PdfDeviceNAttributes.parse(dict);
    }

    return PdfSpecialCsDeviceN(array, names, alternate, tint, attributes);
  }

  /// Whether the attributes dictionary asks for NChannel treatment.
  bool isNChannel() => attributes?.isNChannel() ?? false;

  /// Whether every colourant is `/None`, in which case clause 8.6.6.5 says the
  /// space discards its output and never reverts to the alternate space.
  bool paintsNothing() => colorantNames.every((name) => name == PdfName.none);

  @override
  int getNumberOfComponents() => colorantNames.length;

  @override
  List<double> toRgb(List<double> components) {
    if (paintsNothing()) {
      // Nothing is ever marked, so the page keeps whatever was under it; on a
      // blank page that is white, the same answer /None gives in a Separation.
      return <double>[1.0, 1.0, 1.0];
    }
    // Clause 8.6.6.5: components that name /None are still handed to the tint
    // transform when the space reverts to its alternate, so no filtering here.
    final tints = List<double>.generate(
        colorantNames.length, (i) => PdfColorSpace.componentAt(components, i));
    return alternate.toRgb(tintTransform.evaluate(tints));
  }
}
