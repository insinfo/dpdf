import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function.dart';

/// A type 3 (stitching) function, ISO 32000-1, clause 7.10.4.
///
/// The single input domain is split by `/Bounds` into k subdomains; the k-th
/// subfunction is evaluated on the input re-encoded into `/Encode[2k, 2k+1]`.
class CraftPdfFunctionStitching extends CraftPdfFunction {
  final List<CraftPdfFunction> functions;

  /// The k-1 interior subdomain boundaries, in increasing order.
  final List<double> bounds;

  /// 2k numbers mapping each subdomain onto its subfunction's domain.
  final List<double> encode;

  CraftPdfFunctionStitching(
      super.domain, super.range, this.functions, this.bounds, this.encode);

  static Future<CraftPdfFunctionStitching?> parseDictionary(
      CraftPdfDictionary dict, List<double> domain, List<double>? range) async {
    // A stitching function has exactly one input (clause 7.10.4).
    if (domain.length != 2) return null;

    final functionsArray =
        await dict.arrayEntry(CraftPdfFunctionName.functions);
    final boundsArray = await dict.arrayEntry(CraftPdfFunctionName.bounds);
    final encodeArray = await dict.arrayEntry(CraftPdfFunctionName.encode);
    if (functionsArray == null || encodeArray == null) return null;

    final functions = <CraftPdfFunction>[];
    for (var i = 0; i < functionsArray.size(); i++) {
      final sub = await CraftPdfFunction.parse(await functionsArray.get(i));
      if (sub == null) return null;
      functions.add(sub);
    }
    if (functions.isEmpty) return null;

    final bounds =
        boundsArray == null ? <double>[] : await boundsArray.toDoubleArray();
    final encode = await encodeArray.toDoubleArray();
    if (bounds.length != functions.length - 1) return null;
    if (encode.length < 2 * functions.length) return null;

    return CraftPdfFunctionStitching(domain, range, functions, bounds, encode);
  }

  @override
  int get outputCount {
    final r = range;
    if (r != null) return r.length ~/ 2;
    return functions.first.outputCount;
  }

  @override
  List<double> evaluateClipped(List<double> inputs) {
    final x = inputs.isEmpty ? domain[0] : inputs[0];

    // Subdomain i covers [low, high). Walking up while x is at or past a bound
    // makes the last subdomain closed on the right, which is what the spec
    // asks for at the top of the domain.
    var i = 0;
    while (i < bounds.length && x >= bounds[i]) {
      i++;
    }

    final low = i == 0 ? domain[0] : bounds[i - 1];
    final high = i == bounds.length ? domain[1] : bounds[i];
    final encoded = CraftPdfFunction.interpolate(
        x, low, high, encode[2 * i], encode[2 * i + 1]);

    return List<double>.from(functions[i].evaluate(<double>[encoded]));
  }
}
