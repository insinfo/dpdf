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
/// They are interned here instead of in [PdfName] so that the function
/// package stays self contained.
class PdfFunctionName {
  PdfFunctionName._();

  static final PdfName functionType = PdfName.intern('FunctionType');
  static final PdfName domain = PdfName.intern('Domain');
  static final PdfName range = PdfName.intern('Range');
  static final PdfName size = PdfName.intern('Size');
  static final PdfName bitsPerSample = PdfName.intern('BitsPerSample');
  static final PdfName encode = PdfName.intern('Encode');
  static final PdfName decode = PdfName.intern('Decode');
  static final PdfName order = PdfName.intern('Order');
  static final PdfName c0 = PdfName.intern('C0');
  static final PdfName c1 = PdfName.intern('C1');
  static final PdfName n = PdfName.intern('N');
  static final PdfName functions = PdfName.intern('Functions');
  static final PdfName bounds = PdfName.intern('Bounds');
}

/// A PDF function object as defined by ISO 32000-1, clause 7.10.
///
/// A function maps [inputCount] numbers to [outputCount] numbers. Parsing is
/// asynchronous because the PDF object model resolves indirect references and
/// stream payloads asynchronously; once a function has been parsed every value
/// it needs is held in memory, so [evaluate] is synchronous and can be called
/// from the inner loop of a rasterizer.
abstract class PdfFunction {
  /// The `/Domain` entry: `2 * inputCount` numbers, pairs of `[min, max]`.
  final List<double> domain;

  /// The `/Range` entry: `2 * outputCount` numbers, pairs of `[min, max]`.
  ///
  /// Required for sampled and PostScript functions, optional for the others.
  final List<double>? range;

  PdfFunction(this.domain, this.range);

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
  static Future<PdfFunction?> parse(PdfObject? object) async {
    var resolved = object;
    if (resolved is PdfIndirectReference) {
      resolved = await resolved.targetObject();
    }
    if (resolved == null) return null;

    if (resolved is PdfArray) {
      return await _parseFunctionArray(resolved);
    }
    if (resolved is! PdfDictionary) return null;

    final dict = resolved;
    final type = await dict.integerEntry(PdfFunctionName.functionType);
    if (type == null) return null;

    final domain = await _numbers(dict, PdfFunctionName.domain);
    if (domain == null || domain.length < 2) return null;
    final range = await _numbers(dict, PdfFunctionName.range);

    switch (type) {
      case 0:
        if (dict is! PdfStream) return null;
        return await PdfFunctionSampled.parseStream(dict, domain, range);
      case 2:
        return await PdfFunctionExponential.parseDictionary(
            dict, domain, range);
      case 3:
        return await PdfFunctionStitching.parseDictionary(dict, domain, range);
      case 4:
        if (dict is! PdfStream || range == null) return null;
        return await PdfFunctionPostScript.parseStream(dict, domain, range);
      default:
        return null;
    }
  }

  /// Reads a numeric array entry, returning null when it is absent.
  static Future<List<double>?> _numbers(PdfDictionary dict, PdfName key) async {
    final array = await dict.arrayEntry(key);
    if (array == null) return null;
    return await array.toDoubleArray();
  }

  static Future<PdfFunction?> _parseFunctionArray(PdfArray array) async {
    final parts = <PdfFunction>[];
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
    return PdfFunctionArray(parts);
  }
}

/// An array of n 1-in-1-out functions used where one 1-in-n-out function is
/// expected (ISO 32000-1, clause 8.7.4.5.2 allows this form for shadings).
class PdfFunctionArray extends PdfFunction {
  final List<PdfFunction> functions;

  PdfFunctionArray(this.functions)
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
