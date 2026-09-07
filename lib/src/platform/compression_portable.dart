import 'dart:typed_data';

/// Dependency-free RFC 1950/1951/1952 codecs. Encoding selects stored or
/// fixed-Huffman LZ77 blocks according to their final size;
/// decoding accepts stored, fixed-Huffman and dynamic-Huffman blocks.
const zlib = PortableCompressionCodec();
const gzip = PortableCompressionCodec(gzipFormat: true);

class ZLibEncoder {
  final int level;
  final bool raw;
  const ZLibEncoder({this.level = 6, this.raw = false});
  List<int> convert(List<int> input) {
    if (level < -1 || level > 9) throw ArgumentError.value(level, 'level');
    final data = _bytes(input);
    final result = _deflate(data, level);
    if (raw) return result;
    return Uint8List.fromList([0x78, 0x01, ...result, ..._be(_adler(data))]);
  }
}

class ZLibDecoder {
  final bool raw;
  const ZLibDecoder({this.raw = false});
  List<int> convert(List<int> input) {
    final data = _bytes(input);
    if (raw) return _inflate(data, 0, data.length).bytes;
    if (data.length < 6 ||
        data[0] & 15 != 8 ||
        data[0] >> 4 > 7 ||
        ((data[0] << 8) | data[1]) % 31 != 0) {
      throw const FormatException('Invalid zlib header');
    }
    if (data[1] & 32 != 0) {
      throw const FormatException(
          'Preset compression dictionaries are unsupported');
    }
    final inflated = _inflate(data, 2, data.length - 4);
    if (inflated.end != data.length - 4 ||
        _adler(inflated.bytes) != _readBe(data, data.length - 4)) {
      throw const FormatException('Zlib payload length or checksum mismatch');
    }
    return inflated.bytes;
  }
}

class PortableCompressionCodec {
  final bool gzipFormat;
  const PortableCompressionCodec({this.gzipFormat = false});
  List<int> encode(List<int> input) {
    if (!gzipFormat) return const ZLibEncoder().convert(input);
    final data = _bytes(input);
    return Uint8List.fromList([
      31,
      139,
      8,
      0,
      0,
      0,
      0,
      0,
      0,
      255,
      ..._deflate(data, 6),
      ..._le(_crc(data)),
      ..._le(data.length),
    ]);
  }

  List<int> decode(List<int> input) {
    if (!gzipFormat) return const ZLibDecoder().convert(input);
    final data = _bytes(input);
    final output = BytesBuilder(copy: false);
    var offset = 0;
    do {
      final start = offset;
      if (offset + 10 > data.length ||
          data[offset] != 31 ||
          data[offset + 1] != 139 ||
          data[offset + 2] != 8) {
        throw const FormatException('Invalid gzip member header');
      }
      final flags = data[offset + 3];
      if (flags & 224 != 0) throw const FormatException('Reserved gzip flags');
      offset += 10;
      void require(int length) {
        if (offset + length > data.length) {
          throw const FormatException('Truncated gzip header');
        }
      }

      if (flags & 4 != 0) {
        require(2);
        final size = data[offset] | data[offset + 1] << 8;
        offset += 2;
        require(size);
        offset += size;
      }
      for (final flag in [8, 16]) {
        if (flags & flag != 0) {
          do {
            require(1);
          } while (data[offset++] != 0);
        }
      }
      if (flags & 2 != 0) {
        require(2);
        if ((_crc(data.sublist(start, offset)) & 65535) !=
            (data[offset] | data[offset + 1] << 8)) {
          throw const FormatException('Gzip header checksum mismatch');
        }
        offset += 2;
      }
      final inflated = _inflate(data, offset, data.length);
      offset = inflated.end;
      require(8);
      if (_readLe(data, offset) != _crc(inflated.bytes) ||
          _readLe(data, offset + 4) != (inflated.bytes.length & 0xffffffff)) {
        throw const FormatException('Gzip member checksum or size mismatch');
      }
      output.add(inflated.bytes);
      offset += 8;
    } while (offset < data.length);
    return output.takeBytes();
  }
}

Uint8List _bytes(List<int> input) {
  for (final byte in input) {
    if (byte < 0 || byte > 255) throw ArgumentError('Expected octets');
  }
  return Uint8List.fromList(input);
}

Uint8List _store(Uint8List data) {
  final out = BytesBuilder(copy: false);
  var offset = 0;
  do {
    final left = data.length - offset;
    final size = left > 65535 ? 65535 : left;
    out.add([
      left <= 65535 ? 1 : 0,
      size & 255,
      size >> 8,
      (size ^ 65535) & 255,
      (size ^ 65535) >> 8
    ]);
    out.add(data.sublist(offset, offset + size));
    offset += size;
  } while (offset < data.length);
  return out.takeBytes();
}

class _BitOutput {
  final BytesBuilder bytes = BytesBuilder(copy: false);
  int pending = 0;
  int count = 0;
  void write(int value, int width) {
    pending |= value << count;
    count += width;
    while (count >= 8) {
      bytes.addByte(pending & 255);
      pending >>>= 8;
      count -= 8;
    }
  }

  void code(int value, int width) {
    var reversed = 0;
    for (var i = 0; i < width; i++) {
      reversed = (reversed << 1) | (value & 1);
      value >>>= 1;
    }
    write(reversed, width);
  }

  void literal(int symbol) {
    if (symbol < 144) {
      code(symbol + 48, 8);
    } else if (symbol < 256) {
      code(symbol + 256, 9);
    } else if (symbol < 280) {
      code(symbol - 256, 7);
    } else {
      code(symbol - 88, 8);
    }
  }

  Uint8List finish() {
    if (count != 0) bytes.addByte(pending & 255);
    return bytes.takeBytes();
  }
}

Uint8List _deflate(Uint8List data, int level) {
  final stored = _store(data);
  if (level == 0 || data.isEmpty) return stored;
  final bits = _BitOutput()..write(3, 3); // Final fixed-Huffman block.
  // Absolute positions with ring-buffer predecessor links bound history memory.
  final heads = Int32List(65536)..fillRange(0, 65536, -1);
  final previous = Int32List(32768)..fillRange(0, 32768, -1);
  int hash(int position) =>
      ((data[position] * 251 + data[position + 1]) * 251 + data[position + 2]) &
      65535;
  void remember(int position) {
    if (position + 2 >= data.length) return;
    final bucket = hash(position);
    previous[position & 32767] = heads[bucket];
    heads[bucket] = position;
  }

  final attempts = 8 * (level < 0 ? 6 : level);
  var position = 0;
  while (position < data.length) {
    var bestLength = 0;
    var bestDistance = 0;
    if (position + 2 < data.length) {
      var candidate = heads[hash(position)];
      var remaining = attempts;
      final lower = position > 32768 ? position - 32768 : 0;
      final available = data.length - position;
      final maximum = available < 258 ? available : 258;
      while (candidate >= lower && remaining-- > 0) {
        var length = 0;
        while (length < maximum &&
            data[candidate + length] == data[position + length]) {
          length++;
        }
        if (length > bestLength && length >= 3) {
          bestLength = length;
          bestDistance = position - candidate;
          if (length == maximum) break;
        }
        candidate = previous[candidate & 32767];
      }
    }
    if (bestLength >= 3) {
      var lengthIndex = 0;
      while (lengthIndex + 1 < _lengthBase.length &&
          _lengthBase[lengthIndex + 1] <= bestLength) {
        lengthIndex++;
      }
      var distanceIndex = 0;
      while (distanceIndex + 1 < _distanceBase.length &&
          _distanceBase[distanceIndex + 1] <= bestDistance) {
        distanceIndex++;
      }
      final matchCost = (lengthIndex + 257 < 280 ? 7 : 8) +
          _lengthExtra[lengthIndex] +
          5 +
          _distanceExtra[distanceIndex];
      var literalCost = 0;
      for (var i = 0; i < bestLength; i++) {
        literalCost += data[position + i] < 144 ? 8 : 9;
      }
      if (matchCost < literalCost) {
        bits.literal(lengthIndex + 257);
        bits.write(
            bestLength - _lengthBase[lengthIndex], _lengthExtra[lengthIndex]);
        bits.code(distanceIndex, 5);
        bits.write(bestDistance - _distanceBase[distanceIndex],
            _distanceExtra[distanceIndex]);
      } else {
        bestLength = 0;
      }
    }
    if (bestLength < 3) {
      bits.literal(data[position]);
      bestLength = 1;
    }
    for (var i = 0; i < bestLength; i++) {
      remember(position + i);
    }
    position += bestLength;
  }
  bits.literal(256);
  final fixed = bits.finish();
  return fixed.length < stored.length ? fixed : stored;
}

class _Bits {
  final Uint8List data;
  final int limit;
  int position;
  _Bits(this.data, int start, this.limit) : position = start * 8;
  int take(int count) {
    if (position + count > limit * 8) {
      throw const FormatException('Truncated DEFLATE bitstream');
    }
    var result = 0;
    for (var bit = 0; bit < count; bit++, position++) {
      result |= ((data[position >> 3] >> (position & 7)) & 1) << bit;
    }
    return result;
  }

  void align() => position = (position + 7) & ~7;
}

class _Tree {
  final Map<int, int> symbols = {};
  int maximum = 0;
  _Tree(List<int> lengths, {bool allowEmpty = false}) {
    final counts = List<int>.filled(16, 0);
    for (final length in lengths) {
      if (length < 0 || length > 15) {
        throw const FormatException('Invalid Huffman length');
      }
      if (length != 0) {
        counts[length]++;
        if (length > maximum) maximum = length;
      }
    }
    if (maximum == 0) {
      if (allowEmpty) return;
      throw const FormatException('Empty Huffman alphabet');
    }
    var space = 1;
    final next = List<int>.filled(16, 0);
    var code = 0;
    for (var length = 1; length <= 15; length++) {
      space = space * 2 - counts[length];
      if (space < 0) {
        throw const FormatException('Oversubscribed Huffman alphabet');
      }
      code = (code + counts[length - 1]) << 1;
      next[length] = code;
    }
    if (space != 0 && !(maximum == 1 && counts[1] == 1)) {
      throw const FormatException('Incomplete Huffman alphabet');
    }
    for (var symbol = 0; symbol < lengths.length; symbol++) {
      final length = lengths[symbol];
      if (length != 0) symbols[(1 << length) | next[length]++] = symbol;
    }
  }
  int read(_Bits bits) {
    var code = 0;
    for (var length = 1; length <= maximum; length++) {
      code = (code << 1) | bits.take(1);
      final symbol = symbols[(1 << length) | code];
      if (symbol != null) return symbol;
    }
    throw const FormatException('Unassigned Huffman code');
  }
}

const _lengthBase = [
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  13,
  15,
  17,
  19,
  23,
  27,
  31,
  35,
  43,
  51,
  59,
  67,
  83,
  99,
  115,
  131,
  163,
  195,
  227,
  258
];
const _lengthExtra = [
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  1,
  1,
  1,
  1,
  2,
  2,
  2,
  2,
  3,
  3,
  3,
  3,
  4,
  4,
  4,
  4,
  5,
  5,
  5,
  5,
  0
];
const _distanceBase = [
  1,
  2,
  3,
  4,
  5,
  7,
  9,
  13,
  17,
  25,
  33,
  49,
  65,
  97,
  129,
  193,
  257,
  385,
  513,
  769,
  1025,
  1537,
  2049,
  3073,
  4097,
  6145,
  8193,
  12289,
  16385,
  24577
];
const _distanceExtra = [
  0,
  0,
  0,
  0,
  1,
  1,
  2,
  2,
  3,
  3,
  4,
  4,
  5,
  5,
  6,
  6,
  7,
  7,
  8,
  8,
  9,
  9,
  10,
  10,
  11,
  11,
  12,
  12,
  13,
  13
];

({Uint8List bytes, int end}) _inflate(Uint8List data, int start, int limit) {
  final bits = _Bits(data, start, limit);
  final output = <int>[];
  var last = false;
  while (!last) {
    last = bits.take(1) != 0;
    final kind = bits.take(2);
    if (kind == 0) {
      bits.align();
      final count = bits.take(16);
      if ((count ^ bits.take(16)) != 65535) {
        throw const FormatException('Invalid stored block length');
      }
      for (var i = 0; i < count; i++) {
        output.add(bits.take(8));
      }
      continue;
    }
    if (kind == 3) throw const FormatException('Reserved DEFLATE block type');
    late _Tree literals;
    late _Tree distances;
    if (kind == 1) {
      literals = _Tree(List<int>.generate(
          288,
          (i) => i < 144
              ? 8
              : i < 256
                  ? 9
                  : i < 280
                      ? 7
                      : 8));
      distances = _Tree(List<int>.filled(32, 5));
    } else {
      final literalCount = bits.take(5) + 257;
      final distanceCount = bits.take(5) + 1;
      if (literalCount > 286) {
        throw const FormatException('Invalid literal alphabet size');
      }
      final codeCount = bits.take(4) + 4;
      // Code-length alphabet order specified by RFC 1951 section 3.2.7.
      const sequence = [
        16,
        17,
        18,
        0,
        8,
        7,
        9,
        6,
        10,
        5,
        11,
        4,
        12,
        3,
        13,
        2,
        14,
        1,
        15
      ];
      final codeLengths = List<int>.filled(19, 0);
      for (var i = 0; i < codeCount; i++) {
        codeLengths[sequence[i]] = bits.take(3);
      }
      final codeTree = _Tree(codeLengths);
      final lengths = <int>[];
      while (lengths.length < literalCount + distanceCount) {
        final value = codeTree.read(bits);
        if (value < 16) {
          lengths.add(value);
          continue;
        }
        if (value == 16 && lengths.isEmpty) {
          throw const FormatException('Missing preceding code length');
        }
        final repeat = value == 16
            ? bits.take(2) + 3
            : value == 17
                ? bits.take(3) + 3
                : bits.take(7) + 11;
        final length = value == 16 ? lengths.last : 0;
        if (lengths.length + repeat > literalCount + distanceCount) {
          throw const FormatException('Code-length run exceeds alphabet');
        }
        lengths.addAll(List<int>.filled(repeat, length));
      }
      if (lengths[256] == 0) {
        throw const FormatException('Missing end-of-block symbol');
      }
      literals = _Tree(lengths.sublist(0, literalCount));
      distances = _Tree(lengths.sublist(literalCount), allowEmpty: true);
    }
    while (true) {
      final value = literals.read(bits);
      if (value < 256) {
        output.add(value);
        continue;
      }
      if (value == 256) break;
      if (value > 285) {
        throw const FormatException('Reserved match length symbol');
      }
      final index = value - 257;
      final count = _lengthBase[index] + bits.take(_lengthExtra[index]);
      final distanceSymbol = distances.read(bits);
      if (distanceSymbol >= 30) {
        throw const FormatException('Reserved match distance symbol');
      }
      final distance = _distanceBase[distanceSymbol] +
          bits.take(_distanceExtra[distanceSymbol]);
      if (distance > output.length) {
        throw const FormatException('Match precedes decoded history');
      }
      for (var i = 0; i < count; i++) {
        output.add(output[output.length - distance]);
      }
    }
  }
  return (bytes: Uint8List.fromList(output), end: (bits.position + 7) >> 3);
}

int _adler(List<int> bytes) {
  var a = 1, b = 0;
  for (final byte in bytes) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return ((b << 16) | a).toUnsigned(32);
}

int _crc(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc >>> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff).toUnsigned(32);
}

List<int> _be(int value) =>
    [value >>> 24 & 255, value >>> 16 & 255, value >>> 8 & 255, value & 255];
List<int> _le(int value) => _be(value).reversed.toList();
int _readBe(List<int> bytes, int offset) => (bytes[offset] * 16777216 +
    bytes[offset + 1] * 65536 +
    bytes[offset + 2] * 256 +
    bytes[offset + 3]);
int _readLe(List<int> bytes, int offset) => (bytes[offset] +
    bytes[offset + 1] * 256 +
    bytes[offset + 2] * 65536 +
    bytes[offset + 3] * 16777216);
