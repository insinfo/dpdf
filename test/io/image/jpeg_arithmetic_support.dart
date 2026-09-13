/// Test support: the *encoding* half of ITU-T T.81 Annex D and enough of
/// Annexes F, H and J to build arithmetic-coded JPEG files byte by byte.
///
/// The decoder under test is a transcription of D.2; this is an independent
/// transcription of D.1, so a round trip exercises both sides of the interval
/// arithmetic rather than one implementation against itself.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dpdf/src/io/image/jpeg_arithmetic_decoder.dart';

/// The zig-zag order of T.81 Figure A.6.
const List<int> zigZag = [
  0, 1, 8, 16, 9, 2, 3, 10, //
  17, 24, 32, 25, 18, 11, 4, 5,
  12, 19, 26, 33, 40, 48, 41, 34,
  27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36,
  29, 22, 15, 23, 30, 37, 44, 51,
  58, 59, 52, 45, 38, 31, 39, 46,
  53, 60, 61, 54, 47, 55, 62, 63,
];

/// The adaptive binary arithmetic *encoder* of T.81 D.1.
class ArithmeticEncoder {
  final List<int> bytes = [];

  int _a = 0x10000;
  int _c = 0;
  int _ct = 11;
  int _st = 0;

  /// Index of the byte the flow charts call `B`; -1 before the first output.
  int _bp = -1;

  /// Code_1(S) and Code_0(S) of Figures D.1 and D.2.
  void code(Uint8List stats, int at, int decision) {
    final mps = stats[at] >> 7;
    if (decision == mps) {
      _codeMps(stats, at);
    } else {
      _codeLps(stats, at);
    }
  }

  /// Code_LPS(S), Figure D.3, with the conditional MPS/LPS exchange.
  void _codeLps(Uint8List stats, int at) {
    final state = stats[at];
    final index = state & 0x7F;
    final mps = state >> 7;
    final qe = JpegArithmeticDecoder.stateRow(index)[0];
    _a -= qe;
    if (_a >= qe) {
      _c += _a;
      _a = qe;
    }
    _afterLps(stats, at, index, mps);
    _renorm();
  }

  /// Code_MPS(S), Figure D.4, with the conditional MPS/LPS exchange.
  void _codeMps(Uint8List stats, int at) {
    final state = stats[at];
    final index = state & 0x7F;
    final mps = state >> 7;
    final qe = JpegArithmeticDecoder.stateRow(index)[0];
    _a -= qe;
    if (_a >= 0x8000) return;
    if (_a < qe) {
      _c += _a;
      _a = qe;
    }
    _afterMps(stats, at, index, mps);
    _renorm();
  }

  void _afterMps(Uint8List stats, int at, int index, int mps) {
    stats[at] = (mps << 7) | JpegArithmeticDecoder.stateRow(index)[2];
  }

  void _afterLps(Uint8List stats, int at, int index, int mps) {
    final row = JpegArithmeticDecoder.stateRow(index);
    final sense = row[3] == 1 ? 1 - mps : mps;
    stats[at] = (sense << 7) | row[1];
  }

  /// Renorm_e, Figure D.7.
  void _renorm() {
    do {
      _a = (_a << 1) & 0x1FFFF;
      _c = (_c << 1) & 0xFFFFFFF;
      _ct--;
      if (_ct == 0) {
        _byteOut();
        _ct = 8;
      }
    } while (_a < 0x8000);
  }

  void _emit(int value) {
    bytes.add(value & 0xFF);
    _bp = bytes.length - 1;
  }

  /// Stuff_0, Figure D.11.
  void _stuffZero() {
    if (_bp >= 0 && bytes[_bp] == 0xFF) _emit(0);
  }

  /// Output_stacked_zeros, Figure D.9.
  void _outputStackedZeros() {
    while (_st != 0) {
      _emit(0);
      _st--;
    }
  }

  /// Output_stacked_X'FF's, Figure D.10.
  void _outputStackedFfs() {
    while (_st != 0) {
      _emit(0xFF);
      _emit(0);
      _st--;
    }
  }

  /// Byte_out, Figure D.8, including carry resolution and byte stuffing.
  void _byteOut() {
    final t = _c >> 19;
    if (t > 0xFF) {
      if (_bp < 0) {
        throw StateError('carry out of the first byte of the segment');
      }
      bytes[_bp] = (bytes[_bp] + 1) & 0xFF;
      _stuffZero();
      _outputStackedZeros();
      _emit(t);
    } else if (t == 0xFF) {
      _st++;
    } else {
      _outputStackedFfs();
      _emit(t);
    }
    _c &= 0x7FFFF;
  }

  /// Codes one decision against the fixed estimate of about 0.5 that T.81
  /// F.1.4.4.2 and G.1.3.3 prescribe: Qe = X'5A1D', MPS zero, no adaptation.
  void codeFixed(int decision) {
    const qe = 0x5A1D;
    _a -= qe;
    if (decision == 0) {
      if (_a >= 0x8000) return;
      if (_a < qe) {
        _c += _a;
        _a = qe;
      }
    } else {
      if (_a >= qe) {
        _c += _a;
        _a = qe;
      }
    }
    _renorm();
  }

  /// Flush, Figure D.13, with Clear_final_bits of Figure D.14.
  ///
  /// Trailing zero bytes are kept: T.81 D.1.8 makes discarding them optional
  /// and a decoder is fed zeroes past the end of the segment anyway.
  Uint8List finish() {
    var t = (_c + _a - 1) & 0xFFFF0000;
    if (t < _c) t += 0x8000;
    _c = t;
    _c = (_c << _ct) & 0xFFFFFFF;
    _byteOut();
    _c = (_c << 8) & 0xFFFFFFF;
    _byteOut();
    // Any X'FF' still on the stack can no longer be changed by a carry.
    _outputStackedFfs();
    return Uint8List.fromList(bytes);
  }
}

/// The encoding models of T.81 F.1.4 (DCT) and H.1.2.3 (lossless), the mirror
/// of [JpegArithmeticEntropy].
class ArithmeticModelEncoder {
  final ArithmeticEncoder coder;
  final JpegArithConditioning conditioning;

  final List<Uint8List> dcStats = List.generate(
      4, (_) => Uint8List(JpegArithmeticEntropy.dcStatBins),
      growable: false);
  final List<Uint8List> acStats = List.generate(
      4, (_) => Uint8List(JpegArithmeticEntropy.acStatBins),
      growable: false);
  final Int32List lastDcValue = Int32List(4);
  final Int32List dcContext = Int32List(4);

  ArithmeticModelEncoder(this.coder, this.conditioning);

  void resetDcStats(int table) =>
      dcStats[table].fillRange(0, JpegArithmeticEntropy.dcStatBins, 0);

  void resetAcStats(int table) =>
      acStats[table].fillRange(0, JpegArithmeticEntropy.acStatBins, 0);

  void resetPredictions() {
    lastDcValue.fillRange(0, 4, 0);
    dcContext.fillRange(0, 4, 0);
  }

  int _category(int table, int m, int sign) {
    if (m < ((1 << conditioning.dcL[table]) >> 1)) return 0;
    if (m > ((1 << conditioning.dcU[table]) >> 1)) return 3 + sign;
    return 1 + sign;
  }

  /// Codes the magnitude category and bits of `Sz`, Figures F.6 and F.7.
  /// [at] is the `Sz < 1` context and [x1] the one the run of category
  /// decisions starts from. Returns the leading bit of `Sz`.
  int _codeMagnitude(Uint8List stats, int at, int x1, int sz) {
    if (sz == 0) {
      coder.code(stats, at, 0);
      var context = at + 14;
      // No magnitude bits when Sz is zero.
      assert(context >= 0);
      return 0;
    }
    coder.code(stats, at, 1);
    var m = 1;
    var context = x1;
    while (m * 2 <= sz) {
      coder.code(stats, context, 1);
      m *= 2;
      context++;
    }
    coder.code(stats, context, 0);
    context += 14;
    var bit = m;
    while ((bit >>= 1) != 0) {
      coder.code(stats, context, (sz & bit) != 0 ? 1 : 0);
    }
    return m;
  }

  /// Codes one DC difference for component [ci], per F.1.4.1.
  void encodeDcDifference(int ci, int table, int value) {
    final stats = dcStats[table];
    final s0 = dcContext[ci];
    if (value == 0) {
      coder.code(stats, s0, 0);
      dcContext[ci] = 0;
      lastDcValue[ci] = lastDcValue[ci];
      return;
    }
    coder.code(stats, s0, 1);
    final sign = value < 0 ? 1 : 0;
    coder.code(stats, s0 + 1, sign);
    final magnitude = value < 0 ? -value : value;
    final at = s0 + 2 + sign;
    final m = _codeMagnitude(stats, at, 20, magnitude - 1);
    dcContext[ci] = 4 * _category(table, m, sign);
    lastDcValue[ci] = lastDcValue[ci] + value;
  }

  /// Codes the AC band of one block, per F.1.4.2 and Figure F.5.
  void encodeAcCoefficients(
      int table, Int32List block, int base, int ss, int se, int al) {
    final stats = acStats[table];
    final kx = conditioning.acKx[table];

    int scaled(int k) {
      final value = block[base + zigZag[k]];
      // The point transform is an arithmetic shift towards zero.
      return value >= 0 ? value >> al : -((-value) >> al);
    }

    var last = se;
    while (last >= ss && scaled(last) == 0) {
      last--;
    }

    var k = ss;
    while (k <= se) {
      var at = 3 * (k - 1);
      if (k > last) {
        coder.code(stats, at, 1); // End of band.
        return;
      }
      coder.code(stats, at, 0);
      while (scaled(k) == 0) {
        coder.code(stats, at + 1, 0);
        at += 3;
        k++;
      }
      coder.code(stats, at + 1, 1);
      final value = scaled(k);
      final sign = value < 0 ? 1 : 0;
      coder.codeFixed(sign);
      at += 2;
      final magnitude = (value < 0 ? -value : value) - 1;
      // Table F.5: the first two category decisions share the S0 + 1 bin.
      if (magnitude == 0) {
        coder.code(stats, at, 0);
      } else if (magnitude == 1) {
        coder.code(stats, at, 1);
        coder.code(stats, at, 0);
      } else {
        coder.code(stats, at, 1);
        coder.code(stats, at, 1);
        var m = 2;
        var context = k <= kx ? 189 : 217;
        while (m * 2 <= magnitude) {
          coder.code(stats, context, 1);
          m *= 2;
          context++;
        }
        coder.code(stats, context, 0);
        context += 14;
        var bit = m;
        while ((bit >>= 1) != 0) {
          coder.code(stats, context, (magnitude & bit) != 0 ? 1 : 0);
        }
      }
      k++;
    }
  }

  /// The DC correction bit of a successive-approximation scan, G.1.3.1.
  void encodeCorrectionBit(int bit) => coder.codeFixed(bit);

  /// Codes the refinement of an AC band, G.1.3.3 and Figure G.10.
  ///
  /// [previous] holds the coefficients as the earlier scan left them and
  /// [block] the values at the finer precision.
  void refineAcCoefficients(int table, Int32List previous, Int32List block,
      int base, int ss, int se, int al) {
    final stats = acStats[table];

    int coarse(int k) {
      final value = previous[base + zigZag[k]];
      return value >= 0 ? value >> (al + 1) : -((-value) >> (al + 1));
    }

    int fine(int k) {
      final value = block[base + zigZag[k]];
      return value >= 0 ? value >> al : -((-value) >> al);
    }

    var eobx = se;
    while (eobx > 0 && coarse(eobx) == 0) {
      eobx--;
    }
    var last = se;
    while (last >= ss && fine(last) == 0) {
      last--;
    }

    var k = ss;
    while (k <= se) {
      var at = 3 * (k - 1);
      if (k > eobx) {
        if (k > last) {
          coder.code(stats, at, 1);
          return;
        }
        coder.code(stats, at, 0);
      }
      while (true) {
        if (coarse(k) != 0) {
          // Already nonzero: one correction bit.
          final value = fine(k);
          final magnitude = value < 0 ? -value : value;
          coder.code(stats, at + 2, magnitude & 1);
          break;
        }
        if (fine(k) != 0) {
          coder.code(stats, at + 1, 1);
          coder.codeFixed(fine(k) < 0 ? 1 : 0);
          break;
        }
        coder.code(stats, at + 1, 0);
        at += 3;
        k++;
      }
      k++;
    }
  }

  /// Codes one lossless prediction difference, H.1.2.3 and Table H.3.
  /// Returns the conditioning category of the difference.
  int encodeLosslessDifference(
      int table, int leftCategory, int aboveCategory, int value) {
    final stats = dcStats[table];
    final s0 = 20 * leftCategory + 4 * aboveCategory;
    if (value == 0) {
      coder.code(stats, s0, 0);
      return 0;
    }
    coder.code(stats, s0, 1);
    final sign = value < 0 ? 1 : 0;
    coder.code(stats, s0 + 1, sign);
    final magnitude = value < 0 ? -value : value;
    final x1 = aboveCategory >= 3 ? 129 : 100;
    final m = _codeMagnitude(stats, s0 + 2 + sign, x1, magnitude - 1);
    return _category(table, m, sign);
  }
}

/// A reference inverse DCT, T.81 A.3.3, written straight from the definition
/// so it is independent of the decoder's fast transform.
List<double> referenceIdct(Int32List coefficients, Int32List quant) {
  final out = List<double>.filled(64, 0);
  final cosines = List<double>.generate(
      64, (i) => math.cos((2 * (i ~/ 8) + 1) * (i % 8) * math.pi / 16));
  double c(int u) => u == 0 ? math.sqrt1_2 : 1.0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      var sum = 0.0;
      for (var v = 0; v < 8; v++) {
        for (var u = 0; u < 8; u++) {
          sum += c(u) *
              c(v) *
              coefficients[v * 8 + u] *
              quant[v * 8 + u] *
              cosines[x * 8 + u] *
              cosines[y * 8 + v];
        }
      }
      out[y * 8 + x] = sum / 4;
    }
  }
  return out;
}

/// One component of a frame header, T.81 B.2.2.
class FrameComponent {
  final int id;
  final int h;
  final int v;
  final int quantTable;
  const FrameComponent(this.id, this.h, this.v, [this.quantTable = 0]);
}

/// One component of a scan header, T.81 B.2.3.
class ScanComponent {
  final int id;
  final int dcTable;
  final int acTable;
  const ScanComponent(this.id, [this.dcTable = 0, this.acTable = 0]);
}

/// Assembles a JPEG interchange stream marker by marker, B.1 and B.2.
class JpegBuilder {
  final List<int> bytes = [];

  void marker(int code) => bytes.addAll([0xFF, code]);

  void segment(int code, List<int> payload) {
    marker(code);
    final length = payload.length + 2;
    bytes
      ..addAll([length >> 8, length & 0xFF])
      ..addAll(payload);
  }

  void soi() => marker(0xD8);

  void eoi() => marker(0xD9);

  /// A DQT segment with 8-bit values, in zig-zag order, B.2.4.1.
  void dqt(int id, List<int> naturalOrderTable) {
    final payload = <int>[id];
    for (var i = 0; i < 64; i++) {
      payload.add(naturalOrderTable[zigZag[i]]);
    }
    segment(0xDB, payload);
  }

  /// A frame header. [code] picks the process: 0xC9 for arithmetic sequential,
  /// 0xCA for arithmetic progressive, 0xC3 for lossless Huffman and so on.
  void sof(int code, int precision, int height, int width,
      List<FrameComponent> components) {
    final payload = <int>[
      precision,
      height >> 8,
      height & 0xFF,
      width >> 8,
      width & 0xFF,
      components.length,
    ];
    for (final component in components) {
      payload.addAll([
        component.id,
        (component.h << 4) | component.v,
        component.quantTable,
      ]);
    }
    segment(code, payload);
  }

  /// A DAC segment, B.2.4.3.
  void dac(List<List<int>> entries) {
    final payload = <int>[];
    for (final entry in entries) {
      payload.addAll([(entry[0] << 4) | entry[1], entry[2]]);
    }
    segment(0xCC, payload);
  }

  /// A DRI segment, B.2.4.4.
  void dri(int interval) => segment(0xDD, [interval >> 8, interval & 0xFF]);

  /// An EXP segment, B.3.3.
  void exp(int horizontal, int vertical) =>
      segment(0xDF, [(horizontal << 4) | vertical]);

  /// A scan header followed by its entropy-coded segment, B.2.3.
  void sos(List<ScanComponent> components, Uint8List entropy,
      {int ss = 0, int se = 63, int ah = 0, int al = 0}) {
    final payload = <int>[components.length];
    for (final component in components) {
      payload
          .addAll([component.id, (component.dcTable << 4) | component.acTable]);
    }
    payload.addAll([ss, se, (ah << 4) | al]);
    segment(0xDA, payload);
    bytes.addAll(entropy);
  }

  /// A DHT segment, B.2.4.2.
  void dht(int tableClass, int id, List<int> counts, List<int> values) {
    segment(0xC4, [(tableClass << 4) | id, ...counts, ...values]);
  }

  /// An RSTm marker, B.2.1.
  void restart(int index) => marker(0xD0 + (index & 7));

  Uint8List build() => Uint8List.fromList(bytes);
}

/// A DC Huffman table that gives every difference category of Table H.2 a
/// five-bit code, which is all a lossless scan needs and keeps the canonical
/// assignment trivial: category `n` is the five-bit code `n`.
abstract final class FlatDcTable {
  static const int codeLength = 5;

  static List<int> get counts =>
      [0, 0, 0, 0, 17, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  static List<int> get values => List<int>.generate(17, (i) => i);
}

/// Writes Huffman-coded bits with the byte stuffing of T.81 F.1.2.3.
class HuffmanBitWriter {
  final List<int> bytes = [];
  int _buffer = 0;
  int _count = 0;

  void writeBits(int value, int length) {
    for (var i = length - 1; i >= 0; i--) {
      _buffer = (_buffer << 1) | ((value >> i) & 1);
      _count++;
      if (_count == 8) {
        bytes.add(_buffer & 0xFF);
        if ((_buffer & 0xFF) == 0xFF) bytes.add(0);
        _buffer = 0;
        _count = 0;
      }
    }
  }

  /// Pads the last byte with one bits, which is what F.1.2.3 prescribes.
  Uint8List finish() {
    while (_count != 0) {
      writeBits(1, 1);
    }
    return Uint8List.fromList(bytes);
  }
}
