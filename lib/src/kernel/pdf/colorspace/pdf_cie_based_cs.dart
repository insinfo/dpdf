import 'dart:math' as math;

import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_color_space.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_device_cs.dart';

/// Abstract class for CIE-based color spaces.
abstract class PdfCieBasedCs extends PdfColorSpace {
  /// The `/WhitePoint` key shared by CalGray, CalRGB and Lab.
  static final PdfName whitePointKey = PdfName.intern('WhitePoint');

  /// The `/BlackPoint` key shared by CalGray, CalRGB and Lab.
  static final PdfName blackPointKey = PdfName.intern('BlackPoint');

  /// The `/Gamma` key of CalGray and CalRGB.
  static final PdfName gammaKey = PdfName.intern('Gamma');

  /// The `/Matrix` key of CalRGB.
  static final PdfName matrixKey = PdfName.intern('Matrix');

  PdfCieBasedCs(PdfArray super.pdfObject);

  @override
  bool requiresIndirectStorage() => false;
}

/// Represents a CalGray color space (ISO 32000-1, clause 8.6.5.2, table 63).
///
/// A single component `A` is decoded by the `/Gamma` tone curve and scaled by
/// `/WhitePoint` to give CIE XYZ, which clause 10.3 then turns into device
/// colour. `/WhitePoint` is required by table 63; when a file omits it there
/// is nothing to calibrate against, so the space degrades to DeviceGray, which
/// is what every viewer does with an unusable CalGray dictionary.
class PdfCieBasedCsCalGray extends PdfCieBasedCs {
  /// The `/WhitePoint` entry, or null when the file does not supply one.
  final List<double>? whitePoint;

  /// The `/BlackPoint` entry; defaults to `[0 0 0]` (table 63).
  final List<double> blackPoint;

  /// The `/Gamma` entry; defaults to 1 (table 63).
  final double gamma;

  PdfCieBasedCsCalGray(super.pdfObject,
      {this.whitePoint, List<double>? blackPoint, double? gamma})
      : blackPoint = blackPoint ?? const <double>[0.0, 0.0, 0.0],
        gamma = gamma ?? 1.0;

  /// Builds a CalGray space from its `[/CalGray << ... >>]` array form.
  static Future<PdfCieBasedCsCalGray> parseArray(PdfArray array) async {
    final dict = await array.dictionaryEntry(1);
    if (dict == null) return PdfCieBasedCsCalGray(array);
    return PdfCieBasedCsCalGray(array,
        whitePoint: await PdfCieBasedCsLab.readTriple(
            dict, PdfCieBasedCs.whitePointKey),
        blackPoint: await PdfCieBasedCsLab.readTriple(
            dict, PdfCieBasedCs.blackPointKey),
        gamma: await dict.decimalEntry(PdfCieBasedCs.gammaKey));
  }

  @override
  int getNumberOfComponents() => 1;

  @override
  List<double> toRgb(List<double> components) {
    final a = PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 0));
    final white = whitePoint;
    if (white == null) return PdfDeviceCsGray.grayToRgb(a);

    // Clause 8.6.5.2: X = XW * A^G, Y = YW * A^G, Z = ZW * A^G.
    final decoded = gamma == 1.0 ? a : math.pow(a, gamma).toDouble();
    final value = decoded.isFinite ? decoded : 0.0;
    return PdfCieBasedCsLab.xyzToRgb(
        white[0] * value, white[1] * value, white[2] * value, white);
  }
}

/// Represents a CalRGB color space (ISO 32000-1, clause 8.6.5.3, table 64).
///
/// The three components are decoded by the per-channel `/Gamma` curves and
/// multiplied by `/Matrix` to give CIE XYZ. As with CalGray, `/WhitePoint` is
/// required; a dictionary without one carries no calibration at all, so the
/// components are passed through as sRGB instead of being read as raw XYZ.
class PdfCieBasedCsCalRgb extends PdfCieBasedCs {
  /// The identity `/Matrix` of table 64.
  static const List<double> identityMatrix = <double>[
    1.0, 0.0, 0.0, //
    0.0, 1.0, 0.0, //
    0.0, 0.0, 1.0,
  ];

  /// The `/WhitePoint` entry, or null when the file does not supply one.
  final List<double>? whitePoint;

  /// The `/BlackPoint` entry; defaults to `[0 0 0]` (table 64).
  final List<double> blackPoint;

  /// The `/Gamma` entry; defaults to `[1 1 1]` (table 64).
  final List<double> gamma;

  /// The `/Matrix` entry `[XA YA ZA XB YB ZB XC YC ZC]`; defaults to identity.
  final List<double> matrix;

  PdfCieBasedCsCalRgb(super.pdfObject,
      {this.whitePoint,
      List<double>? blackPoint,
      List<double>? gamma,
      List<double>? matrix})
      : blackPoint = blackPoint ?? const <double>[0.0, 0.0, 0.0],
        gamma = gamma ?? const <double>[1.0, 1.0, 1.0],
        matrix = matrix ?? identityMatrix;

  /// Builds a CalRGB space from its `[/CalRGB << ... >>]` array form.
  static Future<PdfCieBasedCsCalRgb> parseArray(PdfArray array) async {
    final dict = await array.dictionaryEntry(1);
    if (dict == null) return PdfCieBasedCsCalRgb(array);

    final gammaArray = await dict.arrayEntry(PdfCieBasedCs.gammaKey);
    final matrixArray = await dict.arrayEntry(PdfCieBasedCs.matrixKey);
    final gamma = gammaArray != null && gammaArray.size() >= 3
        ? await gammaArray.toDoubleArray()
        : null;
    final matrix = matrixArray != null && matrixArray.size() >= 9
        ? await matrixArray.toDoubleArray()
        : null;

    return PdfCieBasedCsCalRgb(array,
        whitePoint: await PdfCieBasedCsLab.readTriple(
            dict, PdfCieBasedCs.whitePointKey),
        blackPoint: await PdfCieBasedCsLab.readTriple(
            dict, PdfCieBasedCs.blackPointKey),
        gamma: gamma,
        matrix: matrix);
  }

  @override
  int getNumberOfComponents() => 3;

  @override
  List<double> toRgb(List<double> components) {
    final a = PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 0));
    final b = PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 1));
    final c = PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 2));

    final white = whitePoint;
    if (white == null) return <double>[a, b, c];

    final da = _decode(a, gamma[0]);
    final db = _decode(b, gamma[1]);
    final dc = _decode(c, gamma[2]);

    // Clause 8.6.5.3: the matrix is stored column by column, so the first
    // three numbers are the XYZ the A component contributes, and so on.
    final x = matrix[0] * da + matrix[3] * db + matrix[6] * dc;
    final y = matrix[1] * da + matrix[4] * db + matrix[7] * dc;
    final z = matrix[2] * da + matrix[5] * db + matrix[8] * dc;

    return PdfCieBasedCsLab.xyzToRgb(x, y, z, white);
  }

  static double _decode(double value, double exponent) {
    if (exponent == 1.0) return value;
    final decoded = math.pow(value, exponent).toDouble();
    return decoded.isFinite ? decoded : 0.0;
  }
}

/// Represents a Lab color space (ISO 32000-1, clause 8.6.5.4).
///
/// Components are `L*` in 0..100 and `a*`, `b*` inside [range].
class PdfCieBasedCsLab extends PdfCieBasedCs {
  /// Default `/Range`, i.e. `[-100 100 -100 100]` (clause 8.6.5.4, table 65).
  static const List<double> defaultRange = <double>[
    -100.0,
    100.0,
    -100.0,
    100.0
  ];

  /// CIE 1931 tristimulus values of the D65 white point, the white point sRGB
  /// is defined against.
  static const List<double> d65WhitePoint = <double>[0.9505, 1.0, 1.0890];

  /// The `/WhitePoint` entry; PDF files almost always use D50.
  final List<double> whitePoint;

  /// The `/Range` entry: `[aMin aMax bMin bMax]`.
  final List<double> range;

  PdfCieBasedCsLab(super.pdfObject,
      {List<double>? whitePoint, List<double>? range})
      : whitePoint = whitePoint ?? const <double>[0.9642, 1.0, 0.8249],
        range = range ?? defaultRange;

  /// Builds a Lab space from its `[/Lab << ... >>]` array form.
  static Future<PdfCieBasedCsLab> parseArray(PdfArray array) async {
    final dict = await array.dictionaryEntry(1);
    List<double>? whitePoint;
    List<double>? range;
    if (dict != null) {
      whitePoint = await readTriple(dict, PdfCieBasedCs.whitePointKey);
      final r = await dict.arrayEntry(PdfName.intern('Range'));
      if (r != null && r.size() >= 4) {
        range = await r.toDoubleArray();
      }
    }
    return PdfCieBasedCsLab(array, whitePoint: whitePoint, range: range);
  }

  /// Reads a three-number entry such as `/WhitePoint` or `/BlackPoint`.
  ///
  /// Returns null when the entry is absent or too short, which lets each space
  /// apply its own default (or fall back to an uncalibrated conversion).
  static Future<List<double>?> readTriple(
      PdfDictionary dict, PdfName key) async {
    final array = await dict.arrayEntry(key);
    if (array == null || array.size() < 3) return null;
    return array.toDoubleArray();
  }

  @override
  int getNumberOfComponents() => 3;

  @override
  List<double> getComponentRange(int index) {
    if (index == 0) return const <double>[0.0, 100.0];
    if (index == 1) return <double>[range[0], range[1]];
    if (index == 2) return <double>[range[2], range[3]];
    return const <double>[0.0, 1.0];
  }

  @override
  List<double> toRgb(List<double> components) {
    var lStar = PdfColorSpace.componentAt(components, 0);
    var aStar = PdfColorSpace.componentAt(components, 1);
    var bStar = PdfColorSpace.componentAt(components, 2);
    lStar = lStar.clamp(0.0, 100.0).toDouble();
    aStar = aStar.clamp(range[0], range[1]).toDouble();
    bStar = bStar.clamp(range[2], range[3]).toDouble();

    // CIE L*a*b* -> XYZ relative to this space's white point. The 500 and 200
    // divisors and the 16/116 offset are the definition of L*a*b* itself
    // (CIE 15); fy is the lightness axis and a*/b* displace the x and z axes
    // from it.
    final fy = (lStar + 16.0) / 116.0;
    final fx = fy + aStar / 500.0;
    final fz = fy - bStar / 200.0;

    final x = whitePoint[0] * _labInverse(fx);
    final y = whitePoint[1] * _labInverse(fy);
    final z = whitePoint[2] * _labInverse(fz);

    return xyzToRgb(x, y, z, whitePoint);
  }

  /// Converts CIE XYZ relative to [sourceWhite] into sRGB, ISO 32000-1,
  /// clauses 10.2 and 10.3.
  ///
  /// The PDF white point (usually D50) is not the one sRGB assumes, so the
  /// tristimulus values are chromatically adapted to D65 before the sRGB
  /// primaries matrix is applied. Skipping that step tints every neutral on
  /// the page. This is the single XYZ entry point shared by Lab, CalGray and
  /// CalRGB so that the three never disagree about the same colour.
  static List<double> xyzToRgb(
      double x, double y, double z, List<double> sourceWhite) {
    final adapted = _bradfordAdapt(x, y, z, sourceWhite, d65WhitePoint);
    return xyzD65ToRgb(adapted[0], adapted[1], adapted[2]);
  }

  /// Inverse of the L*a*b* companding function.
  ///
  /// Below t = 6/29 the cube root is replaced by its tangent line so that the
  /// curve stays finite in slope near black (CIE 15, clause 8.2.1).
  static double _labInverse(double t) {
    const delta = 6.0 / 29.0;
    if (t > delta) return t * t * t;
    return 3.0 * delta * delta * (t - 4.0 / 29.0);
  }

  /// Bradford chromatic adaptation from [sourceWhite] to [destWhite].
  ///
  /// The matrix converts XYZ into the LMS-like "cone response" space in which
  /// adaptation is a per-channel scale; scaling by destWhite/sourceWhite in
  /// that space maps the source white exactly onto the destination white.
  static List<double> _bradfordAdapt(double x, double y, double z,
      List<double> sourceWhite, List<double> destWhite) {
    const ma = <List<double>>[
      <double>[0.8951, 0.2664, -0.1614],
      <double>[-0.7502, 1.7135, 0.0367],
      <double>[0.0389, -0.0685, 1.0296],
    ];
    const maInverse = <List<double>>[
      <double>[0.9869929, -0.1470543, 0.1599627],
      <double>[0.4323053, 0.5183603, 0.0492912],
      <double>[-0.0085287, 0.0400428, 0.9684867],
    ];

    final source = _multiply(ma, sourceWhite);
    final dest = _multiply(ma, destWhite);
    final cone = _multiply(ma, <double>[x, y, z]);
    for (var i = 0; i < 3; i++) {
      cone[i] = source[i] == 0.0 ? 0.0 : cone[i] * dest[i] / source[i];
    }
    return _multiply(maInverse, cone);
  }

  static List<double> _multiply(List<List<double>> m, List<double> v) {
    return <double>[
      m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
      m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
      m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    ];
  }

  /// Converts D65-relative CIE XYZ into gamma-encoded sRGB in 0..1.
  static List<double> xyzD65ToRgb(double x, double y, double z) {
    // The inverse of the sRGB primaries matrix (IEC 61966-2-1).
    final r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
    final g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
    final b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;
    return <double>[_gamma(r), _gamma(g), _gamma(b)];
  }

  /// The sRGB transfer function: a short linear segment near black followed by
  /// a 1/2.4 power curve (IEC 61966-2-1).
  static double _gamma(double linear) {
    final v = linear <= 0.0031308
        ? 12.92 * linear
        : 1.055 * math.pow(linear.abs(), 1.0 / 2.4).toDouble() - 0.055;
    return PdfColorSpace.clampUnit(v);
  }
}

/// Represents an ICCBased color space.
///
/// The embedded ICC profile is not interpreted; the space behaves like the
/// device space with the same number of components, which is what `/Alternate`
/// would name anyway for the profiles found in practice.
class PdfCieBasedCsIccBased extends PdfCieBasedCs {
  /// The `/N` entry of the profile stream: 1, 3 or 4.
  final int numberOfComponents;

  /// The space named by `/Alternate`, used in place of the profile.
  ///
  /// Clause 8.6.5.5 says a reader that cannot apply the embedded profile shall
  /// use this space instead; only when the entry is missing does it fall back
  /// to the device space with the same number of components.
  final PdfColorSpace? alternate;

  /// The `/Range` entry: `2 * /N` numbers, or null for the `[0 1 ...]`
  /// default of table 66.
  final List<double>? range;

  PdfCieBasedCsIccBased(super.pdfObject,
      [this.numberOfComponents = 3, this.alternate, this.range]);

  /// Builds an ICCBased space from its `[/ICCBased stream]` array form.
  static Future<PdfCieBasedCsIccBased> parseArray(PdfArray array) async {
    final stream = await array.streamEntry(1);
    if (stream == null) return PdfCieBasedCsIccBased(array);

    final n = await stream.integerEntry(PdfName.n);
    // Three components is the least damaging guess for a profile whose /N is
    // missing, since RGB is by far the most common ICCBased flavour.
    final components = n ?? 3;

    // Table 66 forbids an ICCBased alternate, which is also what keeps a file
    // whose /Alternate points back at itself from recursing forever.
    var alternate = await PdfColorSpace.makeColorSpace(
        await stream.get(PdfName.intern('Alternate'), false));
    if (alternate is PdfCieBasedCsIccBased ||
        (alternate != null &&
            alternate.getNumberOfComponents() != components)) {
      alternate = null;
    }

    final rangeArray = await stream.arrayEntry(PdfName.intern('Range'));
    final range = rangeArray != null && rangeArray.size() >= 2 * components
        ? await rangeArray.toDoubleArray()
        : null;

    return PdfCieBasedCsIccBased(array, components, alternate, range);
  }

  @override
  int getNumberOfComponents() => numberOfComponents;

  @override
  List<double> getComponentRange(int index) {
    final r = range;
    if (r == null || 2 * index + 1 >= r.length) {
      return const <double>[0.0, 1.0];
    }
    return <double>[r[2 * index], r[2 * index + 1]];
  }

  @override
  List<double> toRgb(List<double> components) {
    final fallback = alternate;
    if (fallback != null) return fallback.toRgb(components);
    switch (numberOfComponents) {
      case 1:
        return PdfDeviceCsGray.grayToRgb(
            PdfColorSpace.componentAt(components, 0));
      case 4:
        return PdfDeviceCsCmyk.cmykToRgb(
            PdfColorSpace.componentAt(components, 0),
            PdfColorSpace.componentAt(components, 1),
            PdfColorSpace.componentAt(components, 2),
            PdfColorSpace.componentAt(components, 3));
      default:
        return <double>[
          PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 0)),
          PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 1)),
          PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 2)),
        ];
    }
  }
}
