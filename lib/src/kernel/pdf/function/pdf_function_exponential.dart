import 'dart:math' as math;

import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function.dart';

/// A type 2 (exponential interpolation) function, ISO 32000-1, clause 7.10.3.
///
/// `y_j = C0_j + x^N * (C1_j - C0_j)` over a single input.
class CraftPdfFunctionExponential extends CraftPdfFunction {
  /// Function value at the low end of the domain.
  final List<double> c0;

  /// Function value at the high end of the domain.
  final List<double> c1;

  /// The interpolation exponent `/N`.
  final double exponent;

  CraftPdfFunctionExponential(
      super.domain, super.range, this.c0, this.c1, this.exponent);

  static Future<CraftPdfFunctionExponential?> parseDictionary(
      CraftPdfDictionary dict, List<double> domain, List<double>? range) async {
    final n = await dict.decimalEntry(CraftPdfFunctionName.n);
    if (n == null) return null;

    // The defaults of clause 7.10.3 make an unadorned type 2 function the
    // identity ramp from 0 to 1.
    final c0Array = await dict.arrayEntry(CraftPdfFunctionName.c0);
    final c1Array = await dict.arrayEntry(CraftPdfFunctionName.c1);
    final c0 = c0Array == null ? <double>[0.0] : await c0Array.toDoubleArray();
    final c1 = c1Array == null ? <double>[1.0] : await c1Array.toDoubleArray();
    if (c0.isEmpty || c0.length != c1.length) return null;

    return CraftPdfFunctionExponential(domain, range, c0, c1, n);
  }

  @override
  int get outputCount => c0.length;

  @override
  List<double> evaluateClipped(List<double> inputs) {
    final x = inputs.isEmpty ? 0.0 : inputs[0];
    // pow() returns NaN for a negative base with a fractional exponent; the
    // spec only defines such domains for integral N, so fall back to 0 to keep
    // a malformed file from poisoning the whole colour pipeline.
    var factor = exponent == 1.0 ? x : math.pow(x, exponent).toDouble();
    if (factor.isNaN || factor.isInfinite) factor = 0.0;

    final outputs = List<double>.filled(c0.length, 0.0);
    for (var j = 0; j < c0.length; j++) {
      outputs[j] = c0[j] + factor * (c1[j] - c0[j]);
    }
    return outputs;
  }
}
