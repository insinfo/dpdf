import 'dart:typed_data';

/// How the samples of a decoded JPEG are laid out.
enum JpegPixelFormat {
  /// One byte per pixel.
  grayscale,

  /// Three bytes per pixel, red then green then blue.
  rgb,

  /// Four bytes per pixel, cyan, magenta, yellow, black. Produced for a
  /// four-component JPEG, which is what a PDF carrying `/DeviceCMYK` uses.
  cmyk,
}

/// A decoded JPEG.
class JpegImage {
  final int width;
  final int height;
  final JpegPixelFormat format;

  /// Interleaved samples, `bytesPerPixel * width * height` long, row major.
  final Uint8List pixels;

  /// True when the file carried an Adobe APP14 marker asking for the CMYK
  /// values to be read inverted, as Photoshop writes them.
  final bool adobeInverted;

  const JpegImage({
    required this.width,
    required this.height,
    required this.format,
    required this.pixels,
    this.adobeInverted = false,
  });

  int get bytesPerPixel => switch (format) {
        JpegPixelFormat.grayscale => 1,
        JpegPixelFormat.rgb => 3,
        JpegPixelFormat.cmyk => 4,
      };

  @override
  String toString() => 'JpegImage(${width}x$height, ${format.name})';
}

/// The input was not a JPEG this decoder can read.
class JpegDecodeException implements Exception {
  final String message;
  const JpegDecodeException(this.message);
  @override
  String toString() => 'JpegDecodeException: $message';
}

/// A Huffman-coded JPEG decoder, sequential and progressive.
///
/// It reads the DCT-based sequential mode of ITU-T T.81 — the mode PDF's
/// `/DCTDecode` filter carries most often — and the progressive mode of T.81
/// §G, with restart intervals and any component sampling factors, so 4:4:4,
/// 4:2:2 and 4:2:0 files all decode. Arithmetic-coded, lossless and
/// hierarchical files are rejected with a clear message rather than decoded
/// wrongly.
///
/// The IDCT is the AAN float algorithm with the scale factors folded into the
/// dequantisation tables, which is what makes a block cost 8 butterflies per
/// row and column instead of 64 multiplications.
abstract final class JpegDecoder {
  /// Decodes [bytes] to interleaved samples.
  static JpegImage decode(Uint8List bytes) => _Decoder(bytes).decode();

  /// Reads the frame header only: dimensions, component count and whether the
  /// file is one this decoder can read.
  ///
  /// Costs a scan of the markers rather than a decode, so a caller can apply a
  /// size policy before committing to the pixels.
  static JpegInfo probe(Uint8List bytes) => _Decoder(bytes).probe();
}

/// What a JPEG's frame header declares.
class JpegInfo {
  final int width;
  final int height;
  final int components;

  /// False for arithmetic-coded, hierarchical or lossless files, which
  /// [JpegDecoder.decode] refuses. Progressive files are decodable.
  final bool decodable;

  /// Why it is not decodable, when it is not.
  final String? reason;

  const JpegInfo({
    required this.width,
    required this.height,
    required this.components,
    required this.decodable,
    this.reason,
  });

  int get pixelCount => width * height;

  @override
  String toString() => 'JpegInfo(${width}x$height, $components component(s)'
      '${decodable ? '' : ', not decodable: $reason'})';
}

// --- implementation ---------------------------------------------------------

class _Component {
  final int id;
  final int h;
  final int v;
  final int quantTable;

  /// Blocks per MCU row and column for this component: the padded grid, big
  /// enough for whole MCUs, which is what the coefficient store is sized to.
  late int blocksPerLine;
  late int blocksPerColumn;

  /// Blocks a *non-interleaved* scan walks, per T.81 A.2.3. A single-component
  /// scan is tiled over the component's own rounded-up size, not over the
  /// padded MCU grid, so for some widths it visits fewer blocks per row than
  /// [blocksPerLine]. Getting this wrong shears every progressive scan that
  /// carries one component, which is nearly all of them.
  late int blocksPerLineForScan;
  late int blocksPerColumnForScan;

  /// Full-resolution-free plane: one byte per sample at this component's own
  /// resolution, `blocksPerLine * 8` wide.
  late Uint8List plane;
  late int planeStride;

  /// Quantised coefficients in natural (de-zigzagged) order, 64 per block,
  /// row-major over the padded grid. Only progressive files need it: their
  /// scans each contribute some bits of some coefficients, so nothing can be
  /// dequantised or transformed until the last scan has been read. A
  /// sequential file goes straight from block to plane and leaves this null.
  Int32List? coefficients;

  int dcTable = 0;
  int acTable = 0;
  int prediction = 0;

  _Component(this.id, this.h, this.v, this.quantTable);
}

/// Canonical Huffman table plus an 8-bit lookahead, per T.81 F.2.2.3.
class _Huffman {
  /// Symbol for a code, indexed by the next 8 bits; -1 when the code is longer.
  final Int16List lookaheadSymbol = Int16List(256)..fillRange(0, 256, -1);
  final Uint8List lookaheadLength = Uint8List(256);

  final Int32List minCode = Int32List(17);
  final Int32List maxCode = Int32List(17)..fillRange(0, 17, -1);
  final Int32List valPointer = Int32List(17);
  late Uint8List values;

  _Huffman(Uint8List counts, this.values) {
    final sizes = <int>[];
    for (var length = 1; length <= 16; length++) {
      for (var i = 0; i < counts[length - 1]; i++) {
        sizes.add(length);
      }
    }

    var code = 0;
    var index = 0;
    for (var length = 1; length <= 16; length++) {
      valPointer[length] = index;
      minCode[length] = code;
      final count = counts[length - 1];
      if (count == 0) {
        maxCode[length] = -1;
        code <<= 1;
        continue;
      }
      for (var i = 0; i < count; i++) {
        // A canonical code of n bits cannot exceed n bits. A corrupt DHT can
        // declare more codes of a length than that length has room for, and
        // then the lookahead fill would run past its 256 entries; say so
        // instead of throwing a range error the caller cannot classify.
        if (code >= (1 << length)) {
          throw const JpegDecodeException(
              'A Huffman table is over-subscribed: its code lengths do not '
              'form a prefix code.');
        }
        if (length <= 8) {
          // Every 8-bit prefix that starts with this code resolves to it.
          final shift = 8 - length;
          final base = code << shift;
          for (var fill = 0; fill < (1 << shift); fill++) {
            lookaheadSymbol[base + fill] = values[index + i];
            lookaheadLength[base + fill] = length;
          }
        }
        code++;
      }
      index += count;
      maxCode[length] = code - 1;
      code <<= 1;
    }
    if (sizes.length != values.length) {
      throw const JpegDecodeException(
          'A Huffman table declares a different number of codes than symbols.');
    }
  }
}

class _Decoder {
  final Uint8List data;
  int offset = 0;

  final Map<int, Int32List> quantTables = {};
  final Map<int, _Huffman> dcTables = {};
  final Map<int, _Huffman> acTables = {};

  List<_Component> components = const [];
  int frameWidth = 0;
  int frameHeight = 0;
  int maxH = 1;
  int maxV = 1;
  int mcusPerLine = 0;
  int mcusPerColumn = 0;
  int restartInterval = 0;
  bool progressive = false;
  String? refusal;

  /// Geometry and buffers are laid out once, at the first scan, and every later
  /// scan of a progressive file adds to them.
  bool prepared = false;

  /// Run of end-of-band blocks still owed, per T.81 G.1.2.2. It survives from
  /// block to block inside one AC scan and is cleared at every restart.
  int eobrun = 0;

  /// Adobe APP14 colour transform: -1 when absent, otherwise 0, 1 or 2.
  int adobeTransform = -1;
  bool sawAdobe = false;

  // Bit reader state.
  int bitBuffer = 0;
  int bitCount = 0;
  bool hitMarker = false;

  final Float64List _block = Float64List(64);
  final Int32List _coefficients = Int32List(64);

  _Decoder(this.data);

  JpegInfo probe() {
    _readFrameHeader(stopAtScan: true);
    return JpegInfo(
      width: frameWidth,
      height: frameHeight,
      components: components.length,
      decodable: refusal == null,
      reason: refusal,
    );
  }

  JpegImage decode() {
    _readFrameHeader(stopAtScan: false);
    if (refusal != null) throw JpegDecodeException(refusal!);
    // A progressive file only has complete coefficients once every scan is in,
    // so dequantisation and the IDCT run here rather than per block.
    if (progressive) _reconstructProgressive();
    return _assemble();
  }

  // --- marker walk ----------------------------------------------------------

  int _u8() {
    if (offset >= data.length) {
      throw const JpegDecodeException('The file ends inside a marker segment.');
    }
    return data[offset++];
  }

  int _u16() {
    final value = (_u8() << 8) | _u8();
    return value;
  }

  void _readFrameHeader({required bool stopAtScan}) {
    if (data.length < 4 || data[0] != 0xFF || data[1] != 0xD8) {
      throw const JpegDecodeException('No SOI marker; this is not a JPEG.');
    }
    offset = 2;

    while (offset < data.length) {
      var marker = _u8();
      if (marker != 0xFF) continue;
      while (offset < data.length && data[offset] == 0xFF) {
        offset++;
      }
      if (offset >= data.length) break;
      marker = _u8();

      switch (marker) {
        case 0xD8: // SOI
        case 0x01: // TEM
          continue;
        case 0xD9: // EOI
          return;
        case 0xC0: // SOF0 baseline
        case 0xC1: // SOF1 extended sequential
          _readFrame(_u16());
        case 0xC2: // SOF2 progressive
          progressive = true;
          _readFrame(_u16());
        case 0xC3:
        case 0xC5:
        case 0xC6:
        case 0xC7:
          refusal ??= 'Lossless or differential JPEG is not supported.';
          _readFrame(_u16());
        case 0xC9:
        case 0xCA:
        case 0xCB:
        case 0xCD:
        case 0xCE:
        case 0xCF:
          refusal ??= 'Arithmetic-coded JPEG is not supported.';
          _readFrame(_u16());
        case 0xC4: // DHT
          _readHuffmanTables(_u16());
        case 0xDB: // DQT
          _readQuantTables(_u16());
        case 0xDD: // DRI
          _u16();
          restartInterval = _u16();
        case 0xEE: // APP14, Adobe
          _readAdobe(_u16());
        case 0xDA: // SOS
          if (stopAtScan || refusal != null) return;
          _readScan(_u16());
          // A sequential file has one scan; anything after it is trailing data.
          // A progressive file has many, so keep walking markers: the scan
          // reader left `offset` on the next real marker.
          if (!progressive) return;
        default:
          if (marker >= 0xD0 && marker <= 0xD7) continue;
          final length = _u16();
          if (length < 2) {
            throw const JpegDecodeException('A marker segment declares a '
                'length shorter than its own length field.');
          }
          offset += length - 2;
      }
    }
    if (components.isEmpty) {
      throw const JpegDecodeException('The file has no frame header.');
    }
  }

  void _readFrame(int length) {
    final end = offset + length - 2;
    final precision = _u8();
    if (precision != 8) {
      refusal ??= '$precision-bit samples are not supported; '
          'only 8-bit JPEG is.';
    }
    frameHeight = _u16();
    frameWidth = _u16();
    final count = _u8();
    if (frameWidth <= 0 || frameHeight <= 0) {
      throw const JpegDecodeException('The frame declares an empty image.');
    }
    if (count == 0 || count > 4) {
      throw JpegDecodeException('A frame with $count components is not '
          'something this decoder reads.');
    }

    final list = <_Component>[];
    for (var i = 0; i < count; i++) {
      final id = _u8();
      final sampling = _u8();
      final h = sampling >> 4;
      final v = sampling & 0x0F;
      if (h < 1 || h > 4 || v < 1 || v > 4) {
        throw const JpegDecodeException(
            'A component declares an out-of-range sampling factor.');
      }
      list.add(_Component(id, h, v, _u8()));
    }
    components = list;
    maxH = list.map((c) => c.h).reduce((a, b) => a > b ? a : b);
    maxV = list.map((c) => c.v).reduce((a, b) => a > b ? a : b);
    mcusPerLine = (frameWidth + maxH * 8 - 1) ~/ (maxH * 8);
    mcusPerColumn = (frameHeight + maxV * 8 - 1) ~/ (maxV * 8);
    offset = end;
  }

  void _readQuantTables(int length) {
    final end = offset + length - 2;
    while (offset < end) {
      final info = _u8();
      final id = info & 0x0F;
      final precision = info >> 4;
      final table = Int32List(64);
      for (var i = 0; i < 64; i++) {
        table[_zigZag[i]] = precision == 0 ? _u8() : _u16();
      }
      quantTables[id] = table;
    }
    offset = end;
  }

  void _readHuffmanTables(int length) {
    final end = offset + length - 2;
    while (offset < end) {
      final info = _u8();
      final isAc = (info >> 4) == 1;
      final id = info & 0x0F;

      final counts = Uint8List(16);
      var total = 0;
      for (var i = 0; i < 16; i++) {
        counts[i] = _u8();
        total += counts[i];
      }
      if (total > 256) {
        throw const JpegDecodeException(
            'A Huffman table declares more than 256 codes.');
      }
      final values = Uint8List(total);
      for (var i = 0; i < total; i++) {
        values[i] = _u8();
      }
      final table = _Huffman(counts, values);
      if (isAc) {
        acTables[id] = table;
      } else {
        dcTables[id] = table;
      }
    }
    offset = end;
  }

  void _readAdobe(int length) {
    final end = offset + length - 2;
    // 'Adobe' plus version, flags0, flags1, transform.
    if (end - offset >= 11 &&
        data[offset] == 0x41 &&
        data[offset + 1] == 0x64 &&
        data[offset + 2] == 0x6F &&
        data[offset + 3] == 0x62 &&
        data[offset + 4] == 0x65) {
      sawAdobe = true;
      adobeTransform = data[end - 1];
    }
    offset = end;
  }

  // --- entropy-coded scan ---------------------------------------------------

  void _readScan(int length) {
    final headerEnd = offset + length - 2;
    final count = _u8();
    final scan = <_Component>[];
    for (var i = 0; i < count; i++) {
      final id = _u8();
      final tables = _u8();
      final component = components.firstWhere(
        (c) => c.id == id,
        orElse: () => throw JpegDecodeException(
            'The scan names component $id, which the frame does not declare.'),
      );
      component.dcTable = tables >> 4;
      component.acTable = tables & 0x0F;
      scan.add(component);
    }
    // Spectral selection and successive approximation. A sequential scan writes
    // 0/63/0/0 here and the values are then inert, so they are read
    // unconditionally and only the progressive path acts on them.
    final spectralStart = _u8();
    final spectralEnd = _u8();
    final approximation = _u8();
    offset = headerEnd;

    _prepareComponents();

    if (progressive) {
      _readProgressiveScan(
        scan,
        spectralStart,
        spectralEnd,
        approximation >> 4,
        approximation & 0x0F,
      );
      return;
    }

    bitBuffer = 0;
    bitCount = 0;
    hitMarker = false;

    var mcu = 0;
    final total = mcusPerLine * mcusPerColumn;
    final interval = restartInterval == 0 ? total : restartInterval;

    while (mcu < total) {
      for (final component in components) {
        component.prediction = 0;
      }
      final stop = mcu + interval < total ? mcu + interval : total;
      for (; mcu < stop; mcu++) {
        final row = mcu ~/ mcusPerLine;
        final column = mcu % mcusPerLine;
        for (final component in scan) {
          for (var v = 0; v < component.v; v++) {
            for (var h = 0; h < component.h; h++) {
              _decodeBlock(
                component,
                row * component.v + v,
                column * component.h + h,
              );
            }
          }
        }
      }
      if (mcu < total) {
        if (!_skipRestart()) break;
      }
    }
  }

  /// Sizes the per-component grids, planes and — for a progressive file — the
  /// coefficient store.
  ///
  /// It runs once, at the first scan, because a progressive file's later scans
  /// refine what the earlier ones wrote: reallocating per scan, which is safe
  /// for a single sequential scan, would throw away every earlier bit.
  void _prepareComponents() {
    if (prepared) return;
    prepared = true;
    for (final component in components) {
      component.blocksPerLine = mcusPerLine * component.h;
      component.blocksPerColumn = mcusPerColumn * component.v;

      // T.81 A.2.3: a non-interleaved scan tiles the component's own size,
      // ceil(frame * sampling / max) rounded up to whole blocks, which can be
      // narrower than the MCU-padded grid above.
      final width = (frameWidth * component.h + maxH - 1) ~/ maxH;
      final height = (frameHeight * component.v + maxV - 1) ~/ maxV;
      component.blocksPerLineForScan = (width + 7) ~/ 8;
      component.blocksPerColumnForScan = (height + 7) ~/ 8;

      component.planeStride = component.blocksPerLine * 8;
      component.plane =
          Uint8List(component.planeStride * component.blocksPerColumn * 8);
      component.prediction = 0;
      if (progressive) {
        component.coefficients =
            Int32List(component.blocksPerLine * component.blocksPerColumn * 64);
      }
    }
  }

  /// Moves [offset] onto the `0xFF` of the next real marker, stepping over
  /// stuffed `0xFF00` pairs, fill bytes and restart markers.
  ///
  /// A progressive file needs this between scans: the bit reader stops as soon
  /// as it has the bits it wanted, which can be several bytes short of the end
  /// of the entropy-coded segment, and the marker walk must not mistake
  /// leftover compressed bytes for segment headers.
  void _alignToMarker() {
    while (offset + 1 < data.length) {
      if (data[offset] != 0xFF) {
        offset++;
        continue;
      }
      final next = data[offset + 1];
      if (next == 0xFF) {
        offset++; // Fill byte; the marker may still be further along.
        continue;
      }
      if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
        offset += 2; // Stuffing or a restart: still entropy-coded data.
        continue;
      }
      return;
    }
    offset = data.length;
  }

  // --- progressive scans (T.81 G.1.2) ---------------------------------------

  /// Reads one progressive scan into the coefficient store.
  ///
  /// [spectralStart]/[spectralEnd] are Ss/Se, the band of zig-zag positions the
  /// scan carries; [ah]/[al] are the successive-approximation bit positions.
  /// `ah == 0` is a first scan, which sets bits; otherwise it is a refinement,
  /// which appends one bit to what is already there.
  void _readProgressiveScan(
    List<_Component> scan,
    int spectralStart,
    int spectralEnd,
    int ah,
    int al,
  ) {
    if (spectralStart > spectralEnd || spectralEnd > 63) {
      throw const JpegDecodeException(
          'A progressive scan declares a spectral band outside 0..63.');
    }
    if (spectralStart != 0 && scan.length != 1) {
      throw const JpegDecodeException(
          'An AC progressive scan must carry exactly one component.');
    }

    bitBuffer = 0;
    bitCount = 0;
    hitMarker = false;
    eobrun = 0;

    // Only a DC scan may interleave components; an AC scan is always a single
    // component walked block by block in its own raster order.
    final interleaved = scan.length > 1;
    final int total;
    if (interleaved) {
      total = mcusPerLine * mcusPerColumn;
    } else {
      final component = scan.first;
      total = component.blocksPerLineForScan * component.blocksPerColumnForScan;
    }
    final interval = (restartInterval == 0 || restartInterval > total)
        ? total
        : restartInterval;

    var mcu = 0;
    while (mcu < total) {
      // A restart resets the DC predictors and the end-of-band run, so the
      // interval that follows decodes independently of the one before it.
      for (final component in components) {
        component.prediction = 0;
      }
      eobrun = 0;

      final stop = mcu + interval < total ? mcu + interval : total;
      for (; mcu < stop; mcu++) {
        if (interleaved) {
          final row = mcu ~/ mcusPerLine;
          final column = mcu % mcusPerLine;
          for (final component in scan) {
            for (var v = 0; v < component.v; v++) {
              for (var h = 0; h < component.h; h++) {
                _decodeProgressiveBlock(
                  component,
                  row * component.v + v,
                  column * component.h + h,
                  spectralStart,
                  spectralEnd,
                  ah,
                  al,
                );
              }
            }
          }
        } else {
          final component = scan.first;
          _decodeProgressiveBlock(
            component,
            mcu ~/ component.blocksPerLineForScan,
            mcu % component.blocksPerLineForScan,
            spectralStart,
            spectralEnd,
            ah,
            al,
          );
        }
      }
      if (mcu < total) {
        if (!_skipRestart()) break;
      }
    }

    _alignToMarker();
  }

  void _decodeProgressiveBlock(
    _Component component,
    int blockRow,
    int blockColumn,
    int spectralStart,
    int spectralEnd,
    int ah,
    int al,
  ) {
    final coefficients = component.coefficients!;
    final base = (blockRow * component.blocksPerLine + blockColumn) * 64;
    if (base < 0 || base + 64 > coefficients.length) return;

    if (spectralStart == 0) {
      if (spectralEnd != 0) {
        throw const JpegDecodeException(
            'A progressive DC scan must have Se = 0.');
      }
      if (ah == 0) {
        _decodeDcFirst(component, coefficients, base, al);
      } else {
        // Refinement: one more bit of the DC value, at position Al.
        if (_bit() != 0) coefficients[base] |= 1 << al;
      }
      return;
    }

    if (ah == 0) {
      _decodeAcFirst(
          component, coefficients, base, spectralStart, spectralEnd, al);
    } else {
      _decodeAcRefine(
          component, coefficients, base, spectralStart, spectralEnd, al);
    }
  }

  void _decodeDcFirst(
      _Component component, Int32List coefficients, int base, int al) {
    final dc = dcTables[component.dcTable];
    if (dc == null) {
      throw const JpegDecodeException(
          'The scan uses a Huffman table the file never defined.');
    }
    final size = _decodeSymbol(dc);
    final diff = size == 0 ? 0 : _extend(_bits(size), size);
    component.prediction += diff;
    coefficients[base] = component.prediction << al;
  }

  void _decodeAcFirst(_Component component, Int32List coefficients, int base,
      int spectralStart, int spectralEnd, int al) {
    // An end-of-band run swallows whole blocks: the band is all zero here and
    // nothing is read from the stream for this block at all.
    if (eobrun > 0) {
      eobrun--;
      return;
    }

    final ac = acTables[component.acTable];
    if (ac == null) {
      throw const JpegDecodeException(
          'The scan uses a Huffman table the file never defined.');
    }

    var k = spectralStart;
    while (k <= spectralEnd) {
      final symbol = _decodeSymbol(ac);
      final run = symbol >> 4;
      final magnitude = symbol & 0x0F;
      if (magnitude != 0) {
        k += run;
        if (k > spectralEnd) break;
        coefficients[base + _zigZag[k]] =
            _extend(_bits(magnitude), magnitude) << al;
        k++;
        continue;
      }
      if (run != 15) {
        // EOBn: 2^n plus n appended bits blocks end here, this one included,
        // which is why the run is decremented straight away.
        eobrun = 1 << run;
        if (run != 0) eobrun += _bits(run);
        eobrun--;
        return;
      }
      k += 16; // ZRL: sixteen zero coefficients.
    }
  }

  void _decodeAcRefine(_Component component, Int32List coefficients, int base,
      int spectralStart, int spectralEnd, int al) {
    final ac = acTables[component.acTable];
    if (ac == null) {
      throw const JpegDecodeException(
          'The scan uses a Huffman table the file never defined.');
    }

    final positive = 1 << al;
    final negative = -positive;

    var k = spectralStart;
    if (eobrun == 0) {
      while (k <= spectralEnd) {
        final symbol = _decodeSymbol(ac);
        var run = symbol >> 4;
        final magnitude = symbol & 0x0F;
        var value = 0;
        if (magnitude != 0) {
          // A refinement only ever introduces coefficients of magnitude one at
          // this bit position, so the stream carries just the sign.
          value = _bit() != 0 ? positive : negative;
        } else if (run != 15) {
          eobrun = 1 << run;
          if (run != 0) eobrun += _bits(run);
          break; // The correction bits below finish the block.
        }
        // Walk forward over coefficients that were already nonzero, appending
        // a correction bit to each, and over `run` positions that are still
        // zero. The new coefficient, if any, lands on the position after them.
        while (k <= spectralEnd) {
          final at = base + _zigZag[k];
          if (coefficients[at] != 0) {
            if (_bit() != 0 && (coefficients[at] & positive) == 0) {
              coefficients[at] += coefficients[at] >= 0 ? positive : negative;
            }
          } else {
            if (--run < 0) break;
          }
          k++;
        }
        if (magnitude != 0 && k <= spectralEnd) {
          coefficients[base + _zigZag[k]] = value;
        }
        k++;
      }
    }

    if (eobrun > 0) {
      // Inside an end-of-band run no new coefficients appear, but every
      // already-nonzero one in the rest of the band still gets its correction
      // bit. Forgetting these desynchronises the whole scan.
      while (k <= spectralEnd) {
        final at = base + _zigZag[k];
        if (coefficients[at] != 0) {
          if (_bit() != 0 && (coefficients[at] & positive) == 0) {
            coefficients[at] += coefficients[at] >= 0 ? positive : negative;
          }
        }
        k++;
      }
      eobrun--;
    }
  }

  /// Dequantises and transforms every block once all progressive scans are in.
  void _reconstructProgressive() {
    for (final component in components) {
      final coefficients = component.coefficients;
      if (coefficients == null) continue;
      final quant = quantTables[component.quantTable];
      if (quant == null) {
        throw const JpegDecodeException(
            'The frame uses a quantisation table the file never defined.');
      }
      for (var row = 0; row < component.blocksPerColumn; row++) {
        for (var column = 0; column < component.blocksPerLine; column++) {
          final base = (row * component.blocksPerLine + column) * 64;
          for (var i = 0; i < 64; i++) {
            _coefficients[i] = coefficients[base + i];
          }
          _idct(quant, component, row, column);
        }
      }
      // The planes are all that _assemble needs; let the coefficients go.
      component.coefficients = null;
    }
  }

  /// Aligns to the next restart marker. Returns false at end of data.
  bool _skipRestart() {
    bitBuffer = 0;
    bitCount = 0;
    hitMarker = false;
    while (offset + 1 < data.length) {
      if (data[offset] == 0xFF) {
        final marker = data[offset + 1];
        if (marker >= 0xD0 && marker <= 0xD7) {
          offset += 2;
          return true;
        }
        if (marker == 0xD9) return false;
      }
      offset++;
    }
    return false;
  }

  int _bit() {
    if (bitCount == 0) {
      if (hitMarker || offset >= data.length) {
        // Past the end of the entropy-coded data the specification says to
        // feed zero bits, which lets a truncated scan decode as far as it got.
        return 0;
      }
      var byte = data[offset++];
      if (byte == 0xFF) {
        final next = offset < data.length ? data[offset] : 0xD9;
        if (next == 0x00) {
          offset++;
        } else {
          // A real marker: stop consuming and pad with zeroes.
          offset--;
          hitMarker = true;
          byte = 0;
        }
      }
      bitBuffer = byte;
      bitCount = 8;
    }
    bitCount--;
    return (bitBuffer >> bitCount) & 1;
  }

  int _bits(int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      value = (value << 1) | _bit();
    }
    return value;
  }

  int _decodeSymbol(_Huffman table) {
    var code = 0;
    for (var length = 1; length <= 16; length++) {
      code = (code << 1) | _bit();
      final max = table.maxCode[length];
      if (max >= 0 && code <= max) {
        final index = table.valPointer[length] + code - table.minCode[length];
        if (index < 0 || index >= table.values.length) {
          throw const JpegDecodeException(
              'A Huffman code resolves outside its symbol table.');
        }
        return table.values[index];
      }
    }
    throw const JpegDecodeException(
        'A Huffman code is longer than the 16 bits the format allows.');
  }

  /// Sign-extends a [size]-bit value read from the stream, per T.81 F.2.2.1.
  static int _extend(int value, int size) {
    if (size == 0) return 0;
    return value < (1 << (size - 1)) ? value - (1 << size) + 1 : value;
  }

  void _decodeBlock(_Component component, int blockRow, int blockColumn) {
    final dc = dcTables[component.dcTable];
    final ac = acTables[component.acTable];
    final quant = quantTables[component.quantTable];
    if (dc == null || ac == null || quant == null) {
      throw const JpegDecodeException(
          'The scan uses a Huffman or quantisation table the file never '
          'defined.');
    }

    _coefficients.fillRange(0, 64, 0);

    final size = _decodeSymbol(dc);
    final diff = size == 0 ? 0 : _extend(_bits(size), size);
    component.prediction += diff;
    _coefficients[0] = component.prediction;

    var index = 1;
    while (index < 64) {
      final symbol = _decodeSymbol(ac);
      final run = symbol >> 4;
      final magnitude = symbol & 0x0F;
      if (magnitude == 0) {
        if (run != 15) break; // End of block.
        index += 16;
        continue;
      }
      index += run;
      if (index > 63) break;
      _coefficients[_zigZag[index]] = _extend(_bits(magnitude), magnitude);
      index++;
    }

    _idct(quant, component, blockRow, blockColumn);
  }

  // --- inverse DCT ----------------------------------------------------------

  /// AAN scale factors; the dequantisation multipliers fold these in so the
  /// transform itself needs only the butterflies.
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

  final Map<int, Float64List> _dequantCache = {};

  Float64List _multipliers(int table, Int32List quant) {
    return _dequantCache.putIfAbsent(table, () {
      final result = Float64List(64);
      for (var row = 0; row < 8; row++) {
        for (var column = 0; column < 8; column++) {
          final index = row * 8 + column;
          // The trailing 0.125 is the 1/8 the two passes leave behind.
          result[index] =
              quant[index] * _aanScale[row] * _aanScale[column] * 0.125;
        }
      }
      return result;
    });
  }

  void _idct(
      Int32List quant, _Component component, int blockRow, int blockColumn) {
    final multipliers = _multipliers(component.quantTable, quant);
    final block = _block;

    // Pass 1: columns.
    for (var column = 0; column < 8; column++) {
      if (_coefficients[column + 8] == 0 &&
          _coefficients[column + 16] == 0 &&
          _coefficients[column + 24] == 0 &&
          _coefficients[column + 32] == 0 &&
          _coefficients[column + 40] == 0 &&
          _coefficients[column + 48] == 0 &&
          _coefficients[column + 56] == 0) {
        final dc = _coefficients[column] * multipliers[column];
        for (var row = 0; row < 8; row++) {
          block[column + row * 8] = dc;
        }
        continue;
      }

      var tmp0 = _coefficients[column] * multipliers[column];
      var tmp1 = _coefficients[column + 16] * multipliers[column + 16];
      var tmp2 = _coefficients[column + 32] * multipliers[column + 32];
      var tmp3 = _coefficients[column + 48] * multipliers[column + 48];

      var tmp10 = tmp0 + tmp2;
      var tmp11 = tmp0 - tmp2;
      var tmp13 = tmp1 + tmp3;
      var tmp12 = (tmp1 - tmp3) * 1.414213562 - tmp13;

      tmp0 = tmp10 + tmp13;
      tmp3 = tmp10 - tmp13;
      tmp1 = tmp11 + tmp12;
      tmp2 = tmp11 - tmp12;

      var tmp4 = _coefficients[column + 8] * multipliers[column + 8];
      var tmp5 = _coefficients[column + 24] * multipliers[column + 24];
      var tmp6 = _coefficients[column + 40] * multipliers[column + 40];
      var tmp7 = _coefficients[column + 56] * multipliers[column + 56];

      final z13 = tmp6 + tmp5;
      final z10 = tmp6 - tmp5;
      final z11 = tmp4 + tmp7;
      final z12 = tmp4 - tmp7;

      tmp7 = z11 + z13;
      tmp11 = (z11 - z13) * 1.414213562;

      final z5 = (z10 + z12) * 1.847759065;
      tmp10 = 1.082392200 * z12 - z5;
      tmp12 = -2.613125930 * z10 + z5;

      tmp6 = tmp12 - tmp7;
      tmp5 = tmp11 - tmp6;
      tmp4 = tmp10 + tmp5;

      block[column] = tmp0 + tmp7;
      block[column + 56] = tmp0 - tmp7;
      block[column + 8] = tmp1 + tmp6;
      block[column + 48] = tmp1 - tmp6;
      block[column + 16] = tmp2 + tmp5;
      block[column + 40] = tmp2 - tmp5;
      block[column + 32] = tmp3 + tmp4;
      block[column + 24] = tmp3 - tmp4;
    }

    // Pass 2: rows, straight into the component plane.
    final stride = component.planeStride;
    final plane = component.plane;
    final originX = blockColumn * 8;
    final originY = blockRow * 8;

    for (var row = 0; row < 8; row++) {
      final base = row * 8;
      final out = (originY + row) * stride + originX;
      if (out < 0 || out + 8 > plane.length) continue;

      if (block[base + 1] == 0 &&
          block[base + 2] == 0 &&
          block[base + 3] == 0 &&
          block[base + 4] == 0 &&
          block[base + 5] == 0 &&
          block[base + 6] == 0 &&
          block[base + 7] == 0) {
        final value = _clampSample(block[base]);
        for (var i = 0; i < 8; i++) {
          plane[out + i] = value;
        }
        continue;
      }

      var tmp0 = block[base];
      var tmp1 = block[base + 2];
      var tmp2 = block[base + 4];
      var tmp3 = block[base + 6];

      var tmp10 = tmp0 + tmp2;
      var tmp11 = tmp0 - tmp2;
      var tmp13 = tmp1 + tmp3;
      var tmp12 = (tmp1 - tmp3) * 1.414213562 - tmp13;

      tmp0 = tmp10 + tmp13;
      tmp3 = tmp10 - tmp13;
      tmp1 = tmp11 + tmp12;
      tmp2 = tmp11 - tmp12;

      var tmp4 = block[base + 1];
      var tmp5 = block[base + 3];
      var tmp6 = block[base + 5];
      var tmp7 = block[base + 7];

      final z13 = tmp6 + tmp5;
      final z10 = tmp6 - tmp5;
      final z11 = tmp4 + tmp7;
      final z12 = tmp4 - tmp7;

      tmp7 = z11 + z13;
      tmp11 = (z11 - z13) * 1.414213562;

      final z5 = (z10 + z12) * 1.847759065;
      tmp10 = 1.082392200 * z12 - z5;
      tmp12 = -2.613125930 * z10 + z5;

      tmp6 = tmp12 - tmp7;
      tmp5 = tmp11 - tmp6;
      tmp4 = tmp10 + tmp5;

      plane[out] = _clampSample(tmp0 + tmp7);
      plane[out + 7] = _clampSample(tmp0 - tmp7);
      plane[out + 1] = _clampSample(tmp1 + tmp6);
      plane[out + 6] = _clampSample(tmp1 - tmp6);
      plane[out + 2] = _clampSample(tmp2 + tmp5);
      plane[out + 5] = _clampSample(tmp2 - tmp5);
      plane[out + 4] = _clampSample(tmp3 + tmp4);
      plane[out + 3] = _clampSample(tmp3 - tmp4);
    }
  }

  /// Level-shifts by 128 and clamps, which is the range limiting of T.81 A.3.1.
  static int _clampSample(double value) {
    final shifted = value.round() + 128;
    if (shifted < 0) return 0;
    if (shifted > 255) return 255;
    return shifted;
  }

  // --- colour assembly ------------------------------------------------------

  JpegImage _assemble() {
    if (components.isEmpty || !prepared || components.first.plane.isEmpty) {
      throw const JpegDecodeException('The file has no entropy-coded scan.');
    }

    final width = frameWidth;
    final height = frameHeight;
    final count = components.length;

    // Nearest-neighbour upsampling from each component's own resolution. It is
    // what the format's sampling factors describe, and it never invents detail
    // a smoother filter would.
    Uint8List sample(int index) {
      final component = components[index];
      final out = Uint8List(width * height);
      final scaleX = maxH ~/ component.h;
      final scaleY = maxV ~/ component.v;
      final stride = component.planeStride;
      final planeHeight = component.plane.length ~/ stride;
      for (var y = 0; y < height; y++) {
        var sy = y ~/ scaleY;
        if (sy >= planeHeight) sy = planeHeight - 1;
        final rowBase = sy * stride;
        final outBase = y * width;
        for (var x = 0; x < width; x++) {
          var sx = x ~/ scaleX;
          if (sx >= stride) sx = stride - 1;
          out[outBase + x] = component.plane[rowBase + sx];
        }
      }
      return out;
    }

    if (count == 1) {
      return JpegImage(
        width: width,
        height: height,
        format: JpegPixelFormat.grayscale,
        pixels: sample(0),
      );
    }

    if (count == 3) {
      final y = sample(0);
      final cb = sample(1);
      final cr = sample(2);
      // Adobe transform 0 means the three components are already RGB.
      final isRgb = sawAdobe && adobeTransform == 0;
      final pixels = Uint8List(width * height * 3);
      for (var i = 0, p = 0; i < y.length; i++, p += 3) {
        if (isRgb) {
          pixels[p] = y[i];
          pixels[p + 1] = cb[i];
          pixels[p + 2] = cr[i];
        } else {
          _ycc(y[i], cb[i], cr[i], pixels, p);
        }
      }
      return JpegImage(
        width: width,
        height: height,
        format: JpegPixelFormat.rgb,
        pixels: pixels,
      );
    }

    if (count == 4) {
      final c0 = sample(0);
      final c1 = sample(1);
      final c2 = sample(2);
      final k = sample(3);
      // Transform 2 means YCCK: the first three channels are YCbCr and must be
      // converted before they mean anything as CMY.
      final ycck = adobeTransform == 2;
      final pixels = Uint8List(width * height * 4);
      final rgb = Uint8List(3);
      for (var i = 0, p = 0; i < c0.length; i++, p += 4) {
        if (ycck) {
          _ycc(c0[i], c1[i], c2[i], rgb, 0);
          pixels[p] = 255 - rgb[0];
          pixels[p + 1] = 255 - rgb[1];
          pixels[p + 2] = 255 - rgb[2];
        } else {
          pixels[p] = c0[i];
          pixels[p + 1] = c1[i];
          pixels[p + 2] = c2[i];
        }
        pixels[p + 3] = k[i];
      }
      return JpegImage(
        width: width,
        height: height,
        format: JpegPixelFormat.cmyk,
        pixels: pixels,
        adobeInverted: sawAdobe,
      );
    }

    throw JpegDecodeException(
        'A $count-component JPEG has no defined colour interpretation here.');
  }

  /// YCbCr to RGB in fixed point, per JFIF. The constants are the usual
  /// 16-bit-scaled forms of 1.402, 0.344136, 0.714136 and 1.772.
  static void _ycc(int y, int cb, int cr, Uint8List out, int at) {
    final yy = y << 16;
    final b = cb - 128;
    final r = cr - 128;
    out[at] = _clamp((yy + 91881 * r + 32768) >> 16);
    out[at + 1] = _clamp((yy - 22554 * b - 46802 * r + 32768) >> 16);
    out[at + 2] = _clamp((yy + 116130 * b + 32768) >> 16);
  }

  static int _clamp(int value) => value < 0
      ? 0
      : value > 255
          ? 255
          : value;
}

/// The zig-zag order of T.81 Figure A.6, mapping scan position to block index.
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
