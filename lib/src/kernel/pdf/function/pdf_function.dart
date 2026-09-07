import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function_exponential.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function_postscript.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function_sampled.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function_stitching.dart';

/// Dictionary keys used by PDF function objects (ISO 32000-1, clause 7.10).
///
/// They are interned here instead of in [CraftPdfName] so that the function
/// package stays self contained.
class CraftPdfFunctionName {
  CraftPdfFunctionName._();

  static final CraftPdfName functionType = CraftPdfName.intern('FunctionType');
  static final CraftPdfName domain = CraftPdfName.intern('Domain');
  static final CraftPdfName range = CraftPdfName.intern('Range');
  static final CraftPdfName size = CraftPdfName.intern('Size');
  static final CraftPdfName bitsPerSample =
      CraftPdfName.intern('BitsPerSample');
  static final CraftPdfName encode = CraftPdfName.intern('Encode');
  static final CraftPdfName decode = CraftPdfName.intern('Decode');
  static final CraftPdfName order = CraftPdfName.intern('Order');
  static final CraftPdfName c0 = CraftPdfName.intern('C0');
  static final CraftPdfName c1 = CraftPdfName.intern('C1');
  static final CraftPdfName n = CraftPdfName.intern('N');
  static final CraftPdfName functions = CraftPdfName.intern('Functions');
  static final CraftPdfName bounds = CraftPdfName.intern('Bounds');
}

/// A PDF function object as defined by ISO 32000-1, clause 7.10.
///
/// A function maps [inputCount] numbers to [outputCount] numbers. Parsing is
/// asynchronous because the PDF object model resolves indirect references and
/// stream payloads asynchronously; once a function has been parsed every value
/// it needs is held in memory, so [evaluate] is synchronous and can be called
/// from the inner loop of a rasterizer.
abstract class CraftPdfFunction {
  /// The `/Domain` entry: `2 * inputCount` numbers, pairs of `[min, max]`.
  final List<double> domain;

  /// The `/Range` entry: `2 * outputCount` numbers, pairs of `[min, max]`.
  ///
  /// Required for sampled and PostScript functions, optional for the others.
  final List<double>? range;

  CraftPdfFunction(this.domain, this.range);

  /// Number of input values [evaluate] expects.
  int get inputCount => domain.length ~/ 2;

  /// Number of output values [evaluate] produces.
  int get outputCount;

  /// Evaluates the function, clipping inputs to `/Domain` and, when present,
  /// outputs to `/Range`, as clause 7.10.2 requires.
  List<double> evaluate(List<double> inputs) {
    final clipped = List<double>.filled(inputCount, 0.0);
    for (var i = 0; i < inputCount; i++) {
      // Missing inputs are treated as the low end of the domain rather than as
      // an error: broken files are common and a rasterizer must keep going.
      final value = i < inputs.length ? inputs[i] : domain[2 * i];
      clipped[i] = clip(value, domain[2 * i], domain[2 * i + 1]);
    }
    final outputs = evaluateClipped(clipped);
    final r = range;
    if (r != null) {
      for (var j = 0; j < outputs.length && 2 * j + 1 < r.length; j++) {
        outputs[j] = clip(outputs[j], r[2 * j], r[2 * j + 1]);
      }
    }
    return outputs;
  }

  /// Evaluates the function on inputs that are already clipped to `/Domain`.
  ///
  /// The returned list is owned by the caller; [evaluate] clips it in place.
  List<double> evaluateClipped(List<double> inputs);

  /// Clamps [value] into `[min, max]`, tolerating reversed bounds.
  static double clip(double value, double min, double max) {
    if (min > max) {
      final tmp = min;
      min = max;
      max = tmp;
    }
    if (value.isNaN) return min;
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// The `Interpolate` function of clause 7.10.2: maps [x] from `[xmin, xmax]`
  /// onto `[ymin, ymax]`.
  static double interpolate(
      double x, double xmin, double xmax, double ymin, double ymax) {
    // A degenerate source interval carries no information about where in the
    // target interval x lies, so the low end is the only sensible answer.
    if (xmax == xmin) return ymin;
    return ymin + (x - xmin) * (ymax - ymin) / (xmax - xmin);
  }

  /// Parses a function object.
  ///
  /// [object] may be a dictionary, a stream, an indirect reference to either,
  /// or an array of 1-in-1-out functions standing in for a single 1-in-n-out
  /// function (the form shadings use). Returns null when the object is not a
  /// function this implementation understands.
  static Future<CraftPdfFunction?> parse(CraftPdfObject? object) async {
    var resolved = object;
    if (resolved is CraftPdfIndirectReference) {
      resolved = await resolved.targetObject();
    }
    if (resolved == null) return null;

    if (resolved is CraftPdfArray) {
      return await _parseFunctionArray(resolved);
    }
    if (resolved is! CraftPdfDictionary) return null;

    final dict = resolved;
    final type = await dict.integerEntry(CraftPdfFunctionName.functionType);
    if (type == null) return null;

    final domain = await _numbers(dict, CraftPdfFunctionName.domain);
    if (domain == null || domain.length < 2) return null;
    final range = await _numbers(dict, CraftPdfFunctionName.range);

    switch (type) {
      case 0:
        if (dict is! CraftPdfStream) return null;
        return await CraftPdfFunctionSampled.parseStream(dict, domain, range);
      case 2:
        return await CraftPdfFunctionExponential.parseDictionary(
            dict, domain, range);
      case 3:
        return await CraftPdfFunctionStitching.parseDictionary(
            dict, domain, range);
      case 4:
        if (dict is! CraftPdfStream || range == null) return null;
        return await CraftPdfFunctionPostScript.parseStream(
            dict, domain, range);
      default:
        return null;
    }
  }

  /// Reads a numeric array entry, returning null when it is absent.
  static Future<List<double>?> _numbers(
      CraftPdfDictionary dict, CraftPdfName key) async {
    final array = await dict.arrayEntry(key);
    if (array == null) return null;
    return await array.toDoubleArray();
  }

  static Future<CraftPdfFunction?> _parseFunctionArray(
      CraftPdfArray array) async {
    final parts = <CraftPdfFunction>[];
    for (var i = 0; i < array.size(); i++) {
      final part = await parse(await array.get(i));
      // Every member has to be a usable 1-in-1-out function; otherwise the
      // array is not the shading shorthand and we cannot guess an ordering.
      if (part == null || part.inputCount != 1 || part.outputCount != 1) {
        return null;
      }
      parts.add(part);
    }
    if (parts.isEmpty) return null;
    return CraftPdfFunctionArray(parts);
  }
}

/// An array of n 1-in-1-out functions used where one 1-in-n-out function is
/// expected (ISO 32000-1, clause 8.7.4.5.2 allows this form for shadings).
class CraftPdfFunctionArray extends CraftPdfFunction {
  final List<CraftPdfFunction> functions;

  CraftPdfFunctionArray(this.functions)
      : super(List<double>.from(functions.first.domain), null);

  @override
  int get outputCount => functions.length;

  @override
  List<double> evaluateClipped(List<double> inputs) {
    final outputs = List<double>.filled(functions.length, 0.0);
    for (var i = 0; i < functions.length; i++) {
      final result = functions[i].evaluate(inputs);
      outputs[i] = result.isEmpty ? 0.0 : result[0];
    }
    return outputs;
  }
}
