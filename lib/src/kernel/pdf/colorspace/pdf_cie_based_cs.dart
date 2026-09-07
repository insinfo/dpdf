import 'dart:math' as math;

import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_color_space.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_device_cs.dart';

/// Abstract class for CIE-based color spaces.
abstract class PdfCieBasedCs extends PdfColorSpace {
  PdfCieBasedCs(PdfArray super.pdfObject);

  @override
  bool requiresIndirectStorage() => false;
}

/// Represents a CalGray color space.
///
/// The `/Gamma` and `/WhitePoint` entries are ignored: CalGray is only ever a
/// tone curve over a single grey axis, and viewers universally treat it as
/// DeviceGray.
class PdfCieBasedCsCalGray extends PdfCieBasedCs {
  PdfCieBasedCsCalGray(super.pdfObject);

  @override
  int getNumberOfComponents() => 1;

  @override
  List<double> toRgb(List<double> components) {
    return PdfDeviceCsGray.grayToRgb(PdfColorSpace.componentAt(components, 0));
  }
}

/// Represents a CalRGB color space.
///
/// Treated as sRGB: the `/Gamma` and `/Matrix` entries of a CalRGB dictionary
/// almost always describe an sRGB-like space already, and applying them
/// without a full colour-management chain would move colours further from what
/// other viewers show, not closer.
class PdfCieBasedCsCalRgb extends PdfCieBasedCs {
  PdfCieBasedCsCalRgb(super.pdfObject);

  @override
  int getNumberOfComponents() => 3;

  @override
  List<double> toRgb(List<double> components) {
    return <double>[
      PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 0)),
      PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 1)),
      PdfColorSpace.clampUnit(PdfColorSpace.componentAt(components, 2)),
    ];
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
      final wp = await dict.arrayEntry(PdfName.intern('WhitePoint'));
      if (wp != null && wp.size() >= 3) {
        whitePoint = await wp.toDoubleArray();
      }
      final r = await dict.arrayEntry(PdfName.intern('Range'));
      if (r != null && r.size() >= 4) {
        range = await r.toDoubleArray();
      }
    }
    return PdfCieBasedCsLab(array, whitePoint: whitePoint, range: range);
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

    // The PDF white point (usually D50) is not the one sRGB assumes, so adapt
    // the tristimulus values to D65 before applying the sRGB matrix. Skipping
    // this step would tint every neutral in the page.
    final adapted = _bradfordAdapt(x, y, z, whitePoint, d65WhitePoint);

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

  PdfCieBasedCsIccBased(super.pdfObject, [this.numberOfComponents = 3]);

  /// Builds an ICCBased space from its `[/ICCBased stream]` array form.
  static Future<PdfCieBasedCsIccBased> parseArray(PdfArray array) async {
    final stream = await array.streamEntry(1);
    final n = stream == null ? null : await stream.integerEntry(PdfName.n);
    // Three components is the least damaging guess for a profile whose /N is
    // missing, since RGB is by far the most common ICCBased flavour.
    return PdfCieBasedCsIccBased(array, n ?? 3);
  }

  @override
  int getNumberOfComponents() => numberOfComponents;

  @override
  List<double> toRgb(List<double> components) {
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
