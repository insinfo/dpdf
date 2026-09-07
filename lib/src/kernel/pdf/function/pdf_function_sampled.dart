import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function.dart';

/// A type 0 (sampled) function, ISO 32000-1, clause 7.10.2.
///
/// The stream holds a table of `Size[0] * ... * Size[m-1]` samples, each
/// carrying [outputCount] values of `/BitsPerSample` bits, packed as one
/// continuous big-endian bit stream. Values between samples are reconstructed
/// by multilinear interpolation.
class PdfFunctionSampled extends PdfFunction {
  /// Bit widths clause 7.10.2 permits for `/BitsPerSample`.
  static const Set<int> allowedBitsPerSample = {1, 2, 4, 8, 12, 16, 24, 32};

  /// Upper bound on the number of inputs.
  ///
  /// Interpolation visits `2^inputCount` table corners per evaluation, so an
  /// absurd `/Size` in a malformed file must not be able to hang a rasterizer.
  /// Real sampled functions have one or two inputs; four is already exotic.
  static const int maxInputCount = 8;

  /// Number of samples along each input dimension.
  final List<int> size;

  final int bitsPerSample;

  /// 2m numbers mapping the domain of each input onto its sample index range.
  final List<double> encode;

  /// 2n numbers mapping raw sample values onto output values.
  final List<double> decode;

  /// The `/Order` entry as found in the file; see [evaluateClipped].
  final int order;

  final Uint8List _samples;

  /// Distance in samples between neighbours along each input dimension.
  final List<int> _strides;

  final int _outputCount;

  PdfFunctionSampled(super.domain, List<double> super.range, this.size,
      this.bitsPerSample, this.encode, this.decode, this.order, this._samples)
      : _outputCount = range.length ~/ 2,
        _strides = _computeStrides(size);

  /// The first input dimension varies fastest in the sample table, so its
  /// stride is 1 and each later dimension steps over a whole slab of the
  /// preceding ones.
  static List<int> _computeStrides(List<int> size) {
    final strides = List<int>.filled(size.length, 1);
    for (var i = 1; i < size.length; i++) {
      strides[i] = strides[i - 1] * size[i - 1];
    }
    return strides;
  }

  static Future<PdfFunctionSampled?> parseStream(
      PdfStream stream, List<double> domain, List<double>? range) async {
    if (range == null || range.length < 2) return null;

    final sizeArray = await stream.arrayEntry(PdfFunctionName.size);
    final bits = await stream.integerEntry(PdfFunctionName.bitsPerSample);
    if (sizeArray == null || bits == null) return null;
    if (!allowedBitsPerSample.contains(bits)) return null;

    final size = await sizeArray.toIntArray();
    final inputCount = domain.length ~/ 2;
    if (size.length != inputCount || inputCount == 0) return null;
    if (inputCount > maxInputCount) return null;
    for (final s in size) {
      if (s < 1) return null;
    }

    final encodeArray = await stream.arrayEntry(PdfFunctionName.encode);
    final decodeArray = await stream.arrayEntry(PdfFunctionName.decode);
    List<double> encode;
    if (encodeArray != null) {
      encode = await encodeArray.toDoubleArray();
    } else {
      // Default encoding spans the full index range of each dimension.
      encode = <double>[];
      for (final s in size) {
        encode.add(0.0);
        encode.add((s - 1).toDouble());
      }
    }
    if (encode.length < 2 * inputCount) return null;

    final decode = decodeArray != null
        ? await decodeArray.toDoubleArray()
        : List<double>.from(range);
    if (decode.length < range.length) return null;

    final order = await stream.integerEntry(PdfFunctionName.order) ?? 1;

    final bytes = await stream.getBytes();
    if (bytes == null) return null;

    return PdfFunctionSampled(
        domain, range, size, bits, encode, decode, order, bytes);
  }

  @override
  int get outputCount => _outputCount;

  /// The largest raw value a sample can hold, `2^bitsPerSample - 1`.
  int get maxSampleValue => (1 << bitsPerSample) - 1;

  /// Reads output [output] of sample [sampleIndex] from the packed bit stream.
  ///
  /// Returns 0 past the end of the stream so that a truncated table degrades
  /// into black rather than throwing.
  int rawSample(int sampleIndex, int output) {
    final bitPosition = (sampleIndex * _outputCount + output) * bitsPerSample;
    var value = 0;
    for (var bit = 0; bit < bitsPerSample; bit++) {
      final absolute = bitPosition + bit;
      final byteIndex = absolute >> 3;
      if (byteIndex >= _samples.length) return value << (bitsPerSample - bit);
      final bitValue = (_samples[byteIndex] >> (7 - (absolute & 7))) & 1;
      value = (value << 1) | bitValue;
    }
    return value;
  }

  @override
  List<double> evaluateClipped(List<double> inputs) {
    final m = inputCount;

    // Encode each input into a fractional sample index.
    final base = List<int>.filled(m, 0);
    final frac = List<double>.filled(m, 0.0);
    for (var i = 0; i < m; i++) {
      var e = PdfFunction.interpolate(inputs[i], domain[2 * i],
          domain[2 * i + 1], encode[2 * i], encode[2 * i + 1]);
      e = PdfFunction.clip(e, 0.0, (size[i] - 1).toDouble());
      final floor = e.floor();
      // The top sample has no successor, so anchor on the one below it and let
      // the fraction reach 1 instead of indexing past the end of the table.
      base[i] = floor >= size[i] - 1 ? (size[i] > 1 ? size[i] - 2 : 0) : floor;
      frac[i] = size[i] > 1 ? e - base[i] : 0.0;
    }

    // Multilinear interpolation: every corner of the m-dimensional cell
    // contributes with the product of the per-axis weights. `/Order 3` asks
    // for cubic spline interpolation; this implementation deliberately falls
    // back to the linear result, which the spec allows a reader to do and
    // which differs only slightly for the smooth tables Order 3 is used for.
    final outputs = List<double>.filled(_outputCount, 0.0);
    final cornerCount = 1 << m;
    for (var corner = 0; corner < cornerCount; corner++) {
      var weight = 1.0;
      var sampleIndex = 0;
      for (var i = 0; i < m; i++) {
        final high = (corner >> i) & 1 == 1;
        weight *= high ? frac[i] : 1.0 - frac[i];
        var index = base[i] + (high ? 1 : 0);
        if (index > size[i] - 1) index = size[i] - 1;
        sampleIndex += index * _strides[i];
      }
      if (weight == 0.0) continue;
      for (var j = 0; j < _outputCount; j++) {
        outputs[j] += weight * rawSample(sampleIndex, j);
      }
    }

    final max = maxSampleValue.toDouble();
    for (var j = 0; j < _outputCount; j++) {
      outputs[j] = PdfFunction.interpolate(
          outputs[j], 0.0, max, decode[2 * j], decode[2 * j + 1]);
    }
    return outputs;
  }
}
