import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
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

  static Future<PdfSpecialCsSeparation?> parseArray(PdfArray array) async {
    if (array.size() < 4) return null;
    final name = await array.nameEntry(1);
    final alternate = await PdfColorSpace.makeColorSpace(await array.get(2));
    final tint = await PdfFunction.parse(await array.get(3));
    if (name == null || alternate == null || tint == null) return null;
    return PdfSpecialCsSeparation(array, name, alternate, tint);
  }

  @override
  int getNumberOfComponents() => 1;

  @override
  List<double> toRgb(List<double> components) {
    // A /None separation is never painted at all. There is no "no paint" value
    // in RGB, so report white, which is what leaving the area untouched looks
    // like on a blank page.
    if (colorantName == PdfName.none) {
      return <double>[1.0, 1.0, 1.0];
    }
    final tint = PdfColorSpace.componentAt(components, 0);
    return alternate.toRgb(tintTransform.evaluate(<double>[tint]));
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

  PdfSpecialCsDeviceN(PdfArray super.pdfObject, this.colorantNames,
      this.alternate, this.tintTransform);

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

    return PdfSpecialCsDeviceN(array, names, alternate, tint);
  }

  @override
  int getNumberOfComponents() => colorantNames.length;

  @override
  List<double> toRgb(List<double> components) {
    final tints = List<double>.generate(
        colorantNames.length, (i) => PdfColorSpace.componentAt(components, i));
    return alternate.toRgb(tintTransform.evaluate(tints));
  }
}
