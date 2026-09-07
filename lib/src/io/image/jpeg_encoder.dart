import 'dart:typed_data';

import 'jpeg_decoder.dart' show JpegPixelFormat;

/// How chroma is sampled relative to luma.
enum JpegSubsampling {
  /// 4:4:4 — chroma at full resolution. Largest, and the only choice that
  /// leaves saturated edges and thin coloured lines untouched.
  none,

  /// 4:2:0 — chroma at half resolution in both directions. Roughly halves the
  /// chroma data, and is what almost every photographic JPEG uses.
  chroma420,
}

/// A baseline sequential JPEG encoder.
///
/// It writes the mode of ITU-T T.81 that PDF's `/DCTDecode` filter accepts,
/// with the standard Annex K Huffman tables and the Annex K quantisation
/// tables scaled by a quality setting. The forward DCT is AAN with the scale
/// factors folded into the quantisation multipliers.
///
/// The encoding is lossy by construction; the quality setting is the usual
/// 1-to-100 dial, where 75 is a good default for photographs and 90 or above
/// is what you want if the result will be re-encoded again later.
abstract final class JpegEncoder {
  /// Encodes interleaved samples.
  ///
  /// [format] says how [pixels] is laid out; grayscale writes a single
  /// component and RGB writes three. [quality] runs from 1 to 100.
  ///
  /// [subsampling] is ignored for grayscale, which has no chroma.
  static Uint8List encode(
    Uint8List pixels, {
    required int width,
    required int height,
    JpegPixelFormat format = JpegPixelFormat.rgb,
    int quality = 75,
    JpegSubsampling subsampling = JpegSubsampling.chroma420,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('An image must have a positive extent.');
    }
    if (quality < 1 || quality > 100) {
      throw ArgumentError.value(quality, 'quality', 'must be from 1 to 100');
    }
    if (format == JpegPixelFormat.cmyk) {
      throw ArgumentError('Encoding CMYK JPEG is not supported; convert to '
          'RGB or grayscale first.');
    }
    final channels = format == JpegPixelFormat.grayscale ? 1 : 3;
    final needed = width * height * channels;
    if (pixels.length < needed) {
      throw ArgumentError('pixels holds ${pixels.length} bytes, but $needed '
          'are needed for a ${width}x$height ${format.name} image.');
    }

    return _Encoder(
      pixels: pixels,
      width: width,
      height: height,
      grayscale: format == JpegPixelFormat.grayscale,
      quality: quality,
      subsample: format != JpegPixelFormat.grayscale &&
          subsampling == JpegSubsampling.chroma420,
    ).run();
  }
}

class _BitWriter {
  final BytesBuilder _bytes = BytesBuilder();
  int _buffer = 0;
  int _count = 0;

  void byte(int value) => _bytes.addByte(value & 0xff);

  void bytes(List<int> values) => _bytes.add(values);

  void word(int value) {
    _bytes.addByte((value >> 8) & 0xff);
    _bytes.addByte(value & 0xff);
  }

  /// Writes [length] bits of [code], most significant first.
  void bits(int code, int length) {
    for (var i = length - 1; i >= 0; i--) {
      _buffer = (_buffer << 1) | ((code >> i) & 1);
      _count++;
      if (_count == 8) {
        final out = _buffer & 0xff;
        _bytes.addByte(out);
        // A 0xFF byte inside entropy-coded data is followed by a stuffed zero
        // so a decoder never mistakes it for a marker.
        if (out == 0xff) _bytes.addByte(0x00);
        _buffer = 0;
        _count = 0;
      }
    }
  }

  /// Pads the final partial byte with 1 bits, as T.81 F.1.2.3 requires.
  void flushBits() {
    while (_count != 0) {
      bits(1, 1);
    }
  }

  Uint8List takeBytes() => _bytes.takeBytes();
}

/// A canonical Huffman code table built from the spec's `bits` and `values`.
class _HuffmanSpec {
  /// Code lengths per symbol, indexed by symbol value.
  final Uint8List length = Uint8List(256);

  /// Codes per symbol, indexed by symbol value.
  final Int32List code = Int32List(256);

  final List<int> counts;
  final List<int> values;

  _HuffmanSpec(this.counts, this.values) {
    var next = 0;
    var index = 0;
    for (var bitLength = 1; bitLength <= 16; bitLength++) {
      for (var i = 0; i < counts[bitLength - 1]; i++) {
        final symbol = values[index++];
        code[symbol] = next;
        length[symbol] = bitLength;
        next++;
      }
      next <<= 1;
    }
  }
}

class _Encoder {
  final Uint8List pixels;
  final int width;
  final int height;
  final bool grayscale;
  final int quality;
  final bool subsample;

  final _BitWriter out = _BitWriter();

  late final Int32List lumaQuant;
  late final Int32List chromaQuant;
  late final Float64List lumaMultipliers;
  late final Float64List chromaMultipliers;

  final _HuffmanSpec dcLuma = _HuffmanSpec(_dcLumaCounts, _dcLumaValues);
  final _HuffmanSpec acLuma = _HuffmanSpec(_acLumaCounts, _acLumaValues);
  final _HuffmanSpec dcChroma = _HuffmanSpec(_dcChromaCounts, _dcChromaValues);
  final _HuffmanSpec acChroma = _HuffmanSpec(_acChromaCounts, _acChromaValues);

  final Float64List _block = Float64List(64);
  final Int32List _quantized = Int32List(64);

  _Encoder({
    required this.pixels,
    required this.width,
    required this.height,
    required this.grayscale,
    required this.quality,
    required this.subsample,
  }) {
    // The usual mapping from a 1-100 dial to the Annex K scale factor.
    final scale = quality < 50 ? 5000 ~/ quality : 200 - quality * 2;
    lumaQuant = _scaleTable(_lumaQuantBase, scale);
    chromaQuant = _scaleTable(_chromaQuantBase, scale);
    lumaMultipliers = _foldAan(lumaQuant);
    chromaMultipliers = _foldAan(chromaQuant);
  }

  static Int32List _scaleTable(List<int> base, int scale) {
    final table = Int32List(64);
    for (var i = 0; i < 64; i++) {
      final value = (base[i] * scale + 50) ~/ 100;
      table[i] = value < 1 ? 1 : (value > 255 ? 255 : value);
    }
    return table;
  }

  /// AAN forward scale factors, in the reciprocal form the transform needs.
  static const List<double> _aanScale = [
    1.0,
    1.387039845,
    1.306562965,
    1.175875602,
    1.0,
    0.785694958,
    0.541196100,
    0.275899379,
  ];

  static Float64List _foldAan(Int32List quant) {
    final result = Float64List(64);
    for (var row = 0; row < 8; row++) {
      for (var column = 0; column < 8; column++) {
        final index = row * 8 + column;
        // The 1/8 is the normalisation the two DCT passes leave behind.
        result[index] =
            1.0 / (quant[index] * _aanScale[row] * _aanScale[column] * 8.0);
      }
    }
    return result;
  }

  Uint8List run() {
    _writeHeaders();
    _writeScan();
    out.flushBits();
    out.bytes(const [0xFF, 0xD9]); // EOI
    return out.takeBytes();
  }

  // --- headers --------------------------------------------------------------

  void _writeHeaders() {
    out.bytes(const [0xFF, 0xD8]); // SOI

    // APP0 / JFIF, so a viewer knows the density and the colour convention.
    out
      ..bytes(const [0xFF, 0xE0])
      ..word(16)
      ..bytes(const [0x4A, 0x46, 0x49, 0x46, 0x00]) // "JFIF\0"
      ..bytes(const [1, 1]) // version 1.1
      ..byte(0) // density units: none
      ..word(1) // x density
      ..word(1) // y density
      ..bytes(const [0, 0]); // no thumbnail

    // DQT: one table for grayscale, two otherwise.
    final tables = grayscale ? 1 : 2;
    out
      ..bytes(const [0xFF, 0xDB])
      ..word(2 + tables * 65);
    _writeQuantTable(0, lumaQuant);
    if (!grayscale) _writeQuantTable(1, chromaQuant);

    // SOF0.
    final components = grayscale ? 1 : 3;
    out
      ..bytes(const [0xFF, 0xC0])
      ..word(8 + components * 3)
      ..byte(8) // 8-bit samples
      ..word(height)
      ..word(width)
      ..byte(components)
      ..byte(1) // component 1: luma
      ..byte(subsample ? 0x22 : 0x11)
      ..byte(0); // quantisation table 0
    if (!grayscale) {
      out
        ..byte(2)
        ..byte(0x11)
        ..byte(1)
        ..byte(3)
        ..byte(0x11)
        ..byte(1);
    }

    // DHT.
    _writeHuffmanTable(0x00, dcLuma);
    _writeHuffmanTable(0x10, acLuma);
    if (!grayscale) {
      _writeHuffmanTable(0x01, dcChroma);
      _writeHuffmanTable(0x11, acChroma);
    }

    // SOS.
    out
      ..bytes(const [0xFF, 0xDA])
      ..word(6 + components * 2)
      ..byte(components)
      ..byte(1)
      ..byte(0x00); // luma: DC table 0, AC table 0
    if (!grayscale) {
      out
        ..byte(2)
        ..byte(0x11)
        ..byte(3)
        ..byte(0x11);
    }
    out.bytes(const [0x00, 0x3F, 0x00]); // Ss, Se, Ah/Al for a baseline scan
  }

  void _writeQuantTable(int id, Int32List table) {
    out.byte(id); // 8-bit precision in the high nibble, which is 0
    for (var i = 0; i < 64; i++) {
      out.byte(table[_zigZag[i]]);
    }
  }

  void _writeHuffmanTable(int id, _HuffmanSpec spec) {
    out
      ..bytes(const [0xFF, 0xC4])
      ..word(3 + 16 + spec.values.length)
      ..byte(id)
      ..bytes(spec.counts)
      ..bytes(spec.values);
  }

  // --- scan -----------------------------------------------------------------

  void _writeScan() {
    var dcY = 0, dcCb = 0, dcCr = 0;
    final blockSize = subsample ? 16 : 8;

    // Reused per-MCU sample buffers, so a large image does not allocate per
    // block.
    final y = Float64List(blockSize * blockSize);
    final cb = Float64List(blockSize * blockSize);
    final cr = Float64List(blockSize * blockSize);
    final subCb = Float64List(64);
    final subCr = Float64List(64);

    for (var top = 0; top < height; top += blockSize) {
      for (var left = 0; left < width; left += blockSize) {
        _gather(y, cb, cr, left, top, blockSize);

        if (!subsample) {
          dcY = _encodeBlock(y, 8, lumaMultipliers, dcY, dcLuma, acLuma);
          if (!grayscale) {
            dcCb = _encodeBlock(
                cb, 8, chromaMultipliers, dcCb, dcChroma, acChroma);
            dcCr = _encodeBlock(
                cr, 8, chromaMultipliers, dcCr, dcChroma, acChroma);
          }
          continue;
        }

        // Four luma blocks in the order the interleaved scan expects.
        for (final origin in const [0, 8, 128, 136]) {
          dcY = _encodeBlock(y, 16, lumaMultipliers, dcY, dcLuma, acLuma,
              origin: origin);
        }
        // Average each 2x2 chroma group down to one sample.
        for (var row = 0, at = 0; row < 8; row++) {
          for (var column = 0; column < 8; column++, at++) {
            final source = row * 32 + column * 2;
            subCb[at] = (cb[source] +
                    cb[source + 1] +
                    cb[source + 16] +
                    cb[source + 17]) *
                0.25;
            subCr[at] = (cr[source] +
                    cr[source + 1] +
                    cr[source + 16] +
                    cr[source + 17]) *
                0.25;
          }
        }
        dcCb =
            _encodeBlock(subCb, 8, chromaMultipliers, dcCb, dcChroma, acChroma);
        dcCr =
            _encodeBlock(subCr, 8, chromaMultipliers, dcCr, dcChroma, acChroma);
      }
    }
  }

  /// Fills the MCU buffers from the source image, clamping at the edges so a
  /// partial MCU repeats its last row and column rather than reading noise.
  void _gather(Float64List y, Float64List cb, Float64List cr, int left, int top,
      int size) {
    final channels = grayscale ? 1 : 3;
    for (var row = 0, at = 0; row < size; row++) {
      var sy = top + row;
      if (sy >= height) sy = height - 1;
      final rowBase = sy * width * channels;
      for (var column = 0; column < size; column++, at++) {
        var sx = left + column;
        if (sx >= width) sx = width - 1;
        final p = rowBase + sx * channels;
        if (grayscale) {
          y[at] = pixels[p].toDouble() - 128.0;
          continue;
        }
        final r = pixels[p].toDouble();
        final g = pixels[p + 1].toDouble();
        final b = pixels[p + 2].toDouble();
        y[at] = 0.299 * r + 0.587 * g + 0.114 * b - 128.0;
        cb[at] = -0.168736 * r - 0.331264 * g + 0.5 * b;
        cr[at] = 0.5 * r - 0.418688 * g - 0.081312 * b;
      }
    }
  }

  /// Transforms, quantises and entropy-codes one 8x8 block, returning the new
  /// DC predictor.
  int _encodeBlock(
    Float64List source,
    int stride,
    Float64List multipliers,
    int previousDc,
    _HuffmanSpec dc,
    _HuffmanSpec ac, {
    int origin = 0,
  }) {
    final block = _block;
    for (var row = 0; row < 8; row++) {
      final from = origin + row * stride;
      final to = row * 8;
      for (var i = 0; i < 8; i++) {
        block[to + i] = source[from + i];
      }
    }

    _forwardDct(block);

    for (var i = 0; i < 64; i++) {
      final value = block[i] * multipliers[i];
      _quantized[_zigZagInverse[i]] =
          value < 0 ? -((-value) + 0.5).floor() : (value + 0.5).floor();
    }

    // DC: the difference from the previous block of the same component.
    final diff = _quantized[0] - previousDc;
    if (diff == 0) {
      out.bits(dc.code[0], dc.length[0]);
    } else {
      final size = _magnitude(diff);
      out.bits(dc.code[size], dc.length[size]);
      out.bits(_encodedValue(diff, size), size);
    }

    // AC: run-length of zeroes then the magnitude category.
    var last = 63;
    while (last > 0 && _quantized[last] == 0) {
      last--;
    }
    if (last == 0) {
      out.bits(ac.code[0x00], ac.length[0x00]); // EOB
      return _quantized[0];
    }
    var run = 0;
    for (var i = 1; i <= last; i++) {
      if (_quantized[i] == 0) {
        run++;
        continue;
      }
      while (run >= 16) {
        out.bits(ac.code[0xF0], ac.length[0xF0]); // ZRL
        run -= 16;
      }
      final size = _magnitude(_quantized[i]);
      final symbol = (run << 4) | size;
      out.bits(ac.code[symbol], ac.length[symbol]);
      out.bits(_encodedValue(_quantized[i], size), size);
      run = 0;
    }
    if (last != 63) {
      out.bits(ac.code[0x00], ac.length[0x00]); // EOB
    }
    return _quantized[0];
  }

  /// Number of bits needed for [value], its magnitude category.
  static int _magnitude(int value) {
    var magnitude = value < 0 ? -value : value;
    var size = 0;
    while (magnitude != 0) {
      size++;
      magnitude >>= 1;
    }
    return size;
  }

  /// The [size]-bit form of [value]; a negative value is stored as its
  /// one's complement, which is what `_extend` in the decoder undoes.
  static int _encodedValue(int value, int size) {
    return value < 0 ? value - 1 + (1 << size) : value;
  }

  /// AAN forward DCT, in place, rows then columns.
  static void _forwardDct(Float64List block) {
    for (var pass = 0; pass < 2; pass++) {
      // Pass 0 walks the rows, pass 1 the columns of the same buffer.
      final step = pass == 0 ? 1 : 8;
      for (var i = 0; i < 8; i++) {
        final base = pass == 0 ? i * 8 : i;
        final s = step;

        final d0 = block[base];
        final d1 = block[base + s];
        final d2 = block[base + s * 2];
        final d3 = block[base + s * 3];
        final d4 = block[base + s * 4];
        final d5 = block[base + s * 5];
        final d6 = block[base + s * 6];
        final d7 = block[base + s * 7];

        var tmp0 = d0 + d7;
        var tmp7 = d0 - d7;
        var tmp1 = d1 + d6;
        var tmp6 = d1 - d6;
        var tmp2 = d2 + d5;
        var tmp5 = d2 - d5;
        var tmp3 = d3 + d4;
        var tmp4 = d3 - d4;

        var tmp10 = tmp0 + tmp3;
        var tmp13 = tmp0 - tmp3;
        var tmp11 = tmp1 + tmp2;
        var tmp12 = tmp1 - tmp2;

        block[base] = tmp10 + tmp11;
        block[base + s * 4] = tmp10 - tmp11;

        final z1 = (tmp12 + tmp13) * 0.707106781;
        block[base + s * 2] = tmp13 + z1;
        block[base + s * 6] = tmp13 - z1;

        tmp10 = tmp4 + tmp5;
        tmp11 = tmp5 + tmp6;
        tmp12 = tmp6 + tmp7;

        final z5 = (tmp10 - tmp12) * 0.382683433;
        final z2 = tmp10 * 0.541196100 + z5;
        final z4 = tmp12 * 1.306562965 + z5;
        final z3 = tmp11 * 0.707106781;

        final z11 = tmp7 + z3;
        final z13 = tmp7 - z3;

        block[base + s * 5] = z13 + z2;
        block[base + s * 3] = z13 - z2;
        block[base + s] = z11 + z4;
        block[base + s * 7] = z11 - z4;
      }
    }
  }
}

/// Zig-zag order: scan position to natural block index.
const List<int> _zigZag = [
  0, 1, 8, 16, 9, 2, 3, 10, //
  17, 24, 32, 25, 18, 11, 4, 5,
  12, 19, 26, 33, 40, 48, 41, 34,
  27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36,
  29, 22, 15, 23, 30, 37, 44, 51,
  58, 59, 52, 45, 38, 31, 39, 46,
  53, 60, 61, 54, 47, 55, 62, 63,
];

/// Natural block index to scan position, the inverse of [_zigZag].
final List<int> _zigZagInverse = () {
  final inverse = List<int>.filled(64, 0);
  for (var i = 0; i < 64; i++) {
    inverse[_zigZag[i]] = i;
  }
  return inverse;
}();

// The Annex K example tables. They are published in ITU-T T.81 as the
// recommended starting point and are what practically every encoder ships.

const List<int> _lumaQuantBase = [
  16, 11, 10, 16, 24, 40, 51, 61, //
  12, 12, 14, 19, 26, 58, 60, 55,
  14, 13, 16, 24, 40, 57, 69, 56,
  14, 17, 22, 29, 51, 87, 80, 62,
  18, 22, 37, 56, 68, 109, 103, 77,
  24, 35, 55, 64, 81, 104, 113, 92,
  49, 64, 78, 87, 103, 121, 120, 101,
  72, 92, 95, 98, 112, 100, 103, 99,
];

const List<int> _chromaQuantBase = [
  17, 18, 24, 47, 99, 99, 99, 99, //
  18, 21, 26, 66, 99, 99, 99, 99,
  24, 26, 56, 99, 99, 99, 99, 99,
  47, 66, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99,
];

const List<int> _dcLumaCounts = [
  0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0 //
];
const List<int> _dcLumaValues = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];

const List<int> _dcChromaCounts = [
  0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0 //
];
const List<int> _dcChromaValues = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];

const List<int> _acLumaCounts = [
  0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7D //
];
const List<int> _acLumaValues = [
  0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, //
  0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
  0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
  0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0,
  0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16,
  0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
  0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
  0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
  0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
  0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
  0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
  0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
  0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
  0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7,
  0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
  0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5,
  0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4,
  0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
  0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
  0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
  0xF9, 0xFA,
];

const List<int> _acChromaCounts = [
  0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77 //
];
const List<int> _acChromaValues = [
  0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, //
  0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
  0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91,
  0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0,
  0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34,
  0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26,
  0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38,
  0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
  0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
  0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
  0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78,
  0x79, 0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
  0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96,
  0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5,
  0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4,
  0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3,
  0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2,
  0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA,
  0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9,
  0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
  0xF9, 0xFA,
];
