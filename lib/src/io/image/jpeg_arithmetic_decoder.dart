import 'dart:typed_data';

/// The adaptive binary arithmetic decoder of ITU-T T.81 Annex D.
///
/// This is the QM coder: the INITDEC, DECODE, RENORMD and BYTEIN procedures of
/// D.2 driving the 113-entry probability estimation state machine of
/// Table D.3. It decodes one binary decision at a time against a *context*, a
/// single byte of state holding the sense of the more probable symbol in bit 7
/// and the index into Table D.3 in bits 0..6.
///
/// The registers follow D.2.3: `A` is the 17-bit probability interval, `C` the
/// 32-bit code register whose high half `Cx` is compared against `A`, and `CT`
/// counts the bits still buffered in the low half.
class JpegArithmeticDecoder {
  final Uint8List _data;

  /// Index of the next byte BYTEIN will fetch.
  int _bp;

  /// Code register: `Cx` in bits 16..31, the bit buffer in bits 0..15.
  int _c = 0;

  /// Probability interval register, initialised to X'10000' per D.2.7.
  int _a = 0;

  /// Bits of compressed data left in the low half of [_c].
  int _ct = 0;

  bool _marker = false;
  int _markerOffset;

  /// Starts decoding the entropy-coded segment that begins at [start].
  ///
  /// This is the Initdec procedure of T.81 D.2.7, Figure D.22: the interval is
  /// set to its full width and two bytes are shifted into the code register.
  JpegArithmeticDecoder(this._data, int start)
      : _bp = start,
        _markerOffset = start {
    _a = 0x10000;
    _c = 0;
    _byteIn();
    _c = (_c << 8) & 0xFFFFFFFF;
    _byteIn();
    _c = (_c << 8) & 0xFFFFFFFF;
    _ct = 0;
  }

  /// True once the segment's terminating marker has been reached. From then on
  /// the decoder is fed zero bytes, which is what T.81 D.2.6 prescribes.
  bool get markerReached => _marker;

  /// Where the caller should resume reading markers: the first byte of the
  /// marker that ended the segment, or the first byte the decoder did not use.
  int get position => _marker ? _markerOffset : _bp;

  /// The Byte_in procedure of Figures D.20 and D.21.
  ///
  /// A X'FF' in the entropy-coded data is always followed by a stuffed zero;
  /// anything else after it is the marker that terminates the segment, and
  /// after that the decoder is fed zeroes until it has finished.
  void _byteIn() {
    if (_marker) return;
    if (_bp >= _data.length) {
      _marker = true;
      _markerOffset = _data.length;
      return;
    }
    final b = _data[_bp++];
    if (b != 0xFF) {
      _c += b << 8;
      return;
    }
    // Fill bytes may precede the marker, so walk the whole run of X'FF'.
    final firstFf = _bp - 1;
    var at = _bp;
    while (at < _data.length && _data[at] == 0xFF) {
      at++;
    }
    if (at < _data.length && _data[at] == 0x00) {
      _bp = at + 1;
      _c |= 0xFF00; // Unstuff_0: the X'FF' itself enters the register.
      return;
    }
    _marker = true;
    _markerOffset = firstFf;
  }

  /// The Renorm_d procedure of Figure D.19.
  void _renorm() {
    do {
      if (_ct == 0) {
        _byteIn();
        _ct = 8;
      }
      _a = (_a << 1) & 0x1FFFF;
      _c = (_c << 1) & 0xFFFFFFFF;
      _ct--;
    } while (_a < 0x8000);
  }

  void _afterMps(Uint8List stats, int at, int index, int mps) {
    stats[at] = (mps << 7) | _nextMps[index];
  }

  void _afterLps(Uint8List stats, int at, int index, int mps) {
    final sense = _switchMps[index] == 1 ? 1 - mps : mps;
    stats[at] = (sense << 7) | _nextLps[index];
  }

  /// Decodes one binary decision against the context stored at [at] in
  /// [stats]. This is the Decode procedure of Figure D.16 together with the
  /// conditional exchanges of Figures D.17 and D.18.
  int decode(Uint8List stats, int at) {
    final state = stats[at];
    final index = state & 0x7F;
    final mps = state >> 7;
    final qe = _qeValue[index];

    _a -= qe;
    final int d;
    if ((_c >> 16) < _a) {
      if (_a >= 0x8000) return mps;
      // Cond_MPS_exchange, Figure D.18.
      if (_a < qe) {
        d = 1 - mps;
        _afterLps(stats, at, index, mps);
      } else {
        d = mps;
        _afterMps(stats, at, index, mps);
      }
    } else {
      // Cond_LPS_exchange, Figure D.17.
      _c -= _a << 16;
      if (_a < qe) {
        d = mps;
        _afterMps(stats, at, index, mps);
      } else {
        d = 1 - mps;
        _afterLps(stats, at, index, mps);
      }
      _a = qe;
    }
    _renorm();
    return d;
  }

  /// Decodes one decision against the fixed estimate of about 0.5 that T.81
  /// uses for the sign of an AC coefficient (F.1.4.4.2) and for the
  /// successive-approximation correction bits (G.1.3.1, G.1.3.3):
  /// Qe = X'5A1D' with an MPS of zero, and *no* adaptation — the estimate is
  /// fixed, so no state is carried between decisions.
  int decodeFixed() {
    const qe = 0x5A1D;
    _a -= qe;
    final int d;
    if ((_c >> 16) < _a) {
      if (_a >= 0x8000) return 0;
      d = _a < qe ? 1 : 0;
    } else {
      _c -= _a << 16;
      d = _a < qe ? 0 : 1;
      _a = qe;
    }
    _renorm();
    return d;
  }

  /// Qe values of Table D.3, in index order.
  static const List<int> _qeValue = [
    0x5A1D, 0x2586, 0x1114, 0x080B, 0x03D8, 0x01DA, 0x00E5, 0x006F, //
    0x0036, 0x001A, 0x000D, 0x0006, 0x0003, 0x0001, 0x5A7F, 0x3F25,
    0x2CF2, 0x207C, 0x17B9, 0x1182, 0x0CEF, 0x09A1, 0x072F, 0x055C,
    0x0406, 0x0303, 0x0240, 0x01B1, 0x0144, 0x00F5, 0x00B7, 0x008A,
    0x0068, 0x004E, 0x003B, 0x002C, 0x5AE1, 0x484C, 0x3A0D, 0x2EF1,
    0x261F, 0x1F33, 0x19A8, 0x1518, 0x1177, 0x0E74, 0x0BFB, 0x09F8,
    0x0861, 0x0706, 0x05CD, 0x04DE, 0x040F, 0x0363, 0x02D4, 0x025C,
    0x01F8, 0x01A4, 0x0160, 0x0125, 0x00F6, 0x00CB, 0x00AB, 0x008F,
    0x5B12, 0x4D04, 0x412C, 0x37D8, 0x2FE8, 0x293C, 0x2379, 0x1EDF,
    0x1AA9, 0x174E, 0x1424, 0x119C, 0x0F6B, 0x0D51, 0x0BB6, 0x0A40,
    0x5832, 0x4D1C, 0x438E, 0x3BDD, 0x34EE, 0x2EAE, 0x299A, 0x2516,
    0x5570, 0x4CA9, 0x44D9, 0x3E22, 0x3824, 0x32B4, 0x2E17, 0x56A8,
    0x4F46, 0x47E5, 0x41CF, 0x3C3D, 0x375E, 0x5231, 0x4C0F, 0x4639,
    0x415E, 0x5627, 0x50E7, 0x4B85, 0x5597, 0x504F, 0x5A10, 0x5522,
    0x59EB,
  ];

  /// Next_Index_MPS of Table D.3.
  static const List<int> _nextMps = [
    1, 2, 3, 4, 5, 6, 7, 8, //
    9, 10, 11, 12, 13, 13, 15, 16,
    17, 18, 19, 20, 21, 22, 23, 24,
    25, 26, 27, 28, 29, 30, 31, 32,
    33, 34, 35, 9, 37, 38, 39, 40,
    41, 42, 43, 44, 45, 46, 47, 48,
    49, 50, 51, 52, 53, 54, 55, 56,
    57, 58, 59, 60, 61, 62, 63, 32,
    65, 66, 67, 68, 69, 70, 71, 72,
    73, 74, 75, 76, 77, 78, 79, 48,
    81, 82, 83, 84, 85, 86, 87, 71,
    89, 90, 91, 92, 93, 94, 86, 96,
    97, 98, 99, 100, 93, 102, 103, 104,
    99, 106, 107, 103, 109, 107, 111, 109,
    111,
  ];

  /// Next_Index_LPS of Table D.3.
  static const List<int> _nextLps = [
    1, 14, 16, 18, 20, 23, 25, 28, //
    30, 33, 35, 9, 10, 12, 15, 36,
    38, 39, 40, 42, 43, 45, 46, 48,
    49, 51, 52, 54, 56, 57, 59, 60,
    62, 63, 32, 33, 37, 64, 65, 67,
    68, 69, 70, 72, 73, 74, 75, 77,
    78, 79, 48, 50, 50, 51, 52, 53,
    54, 55, 56, 57, 58, 59, 61, 61,
    65, 80, 81, 82, 83, 84, 86, 87,
    87, 72, 72, 74, 74, 75, 77, 77,
    80, 88, 89, 90, 91, 92, 93, 86,
    88, 95, 96, 97, 99, 99, 93, 95,
    101, 102, 103, 104, 99, 105, 106, 107,
    103, 105, 108, 109, 110, 111, 110, 112,
    112,
  ];

  /// Switch_MPS of Table D.3.
  static const List<int> _switchMps = [
    1, 0, 0, 0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, 0, 1, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 1, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 0, 0, 0, 0, 0, 0, 0,
    1, 0, 0, 0, 0, 0, 0, 1,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 1, 0, 0, 0, 0, 1, 0,
    1,
  ];

  /// Table D.3 exposed for validation: `[Qe, NLPS, NMPS, SWITCH]` per index.
  static List<int> stateRow(int index) => [
        _qeValue[index],
        _nextLps[index],
        _nextMps[index],
        _switchMps[index],
      ];

  /// Number of rows in Table D.3.
  static int get stateCount => _qeValue.length;
}

/// The conditioning parameters a DAC marker segment carries, per T.81 B.2.4.3.
///
/// `L` and `U` bound the "small difference" category of the DC and lossless
/// models (F.1.4.4.1.2); `Kx` splits the AC magnitude contexts (F.1.4.4.2).
/// The defaults are the ones the SOI marker establishes: L = 0, U = 1, Kx = 5.
class JpegArithConditioning {
  final Uint8List dcL = Uint8List(4);
  final Uint8List dcU = Uint8List(4)..fillRange(0, 4, 1);
  final Uint8List acKx = Uint8List(4)..fillRange(0, 4, 5);

  /// Applies one `Tc`/`Tb`/`Cs` triple from a DAC segment.
  void apply(int tc, int tb, int cs) {
    if (tb < 0 || tb > 3) {
      throw ArgumentError.value(tb, 'tb', 'DAC destination must be 0..3');
    }
    if (tc == 0) {
      final l = cs & 0x0F;
      final u = cs >> 4;
      if (l > u) {
        throw ArgumentError.value(
            cs, 'cs', 'DAC conditioning requires 0 <= L <= U <= 15');
      }
      dcL[tb] = l;
      dcU[tb] = u;
    } else if (tc == 1) {
      if (cs < 1 || cs > 63) {
        throw ArgumentError.value(cs, 'cs', 'DAC Kx must be 1..63');
      }
      acKx[tb] = cs;
    } else {
      throw ArgumentError.value(tc, 'tc', 'DAC table class must be 0 or 1');
    }
  }
}

/// The statistical models of T.81 F.1.4.4, G.1.3.3.1 and H.1.2.3 driving a
/// [JpegArithmeticDecoder].
///
/// One instance holds the four DC and four AC statistics areas a scan may use
/// plus the single fixed-probability bin the sign of an AC coefficient and the
/// refinement bits are coded with.
class JpegArithmeticEntropy {
  /// Bins a DC statistics area needs: 49 for the DCT model of Table F.4, 158
  /// for the two-dimensional lossless model of Table H.3.
  static const int dcStatBins = 158;

  /// Bins an AC statistics area needs, per Table F.5: the largest context is
  /// X2 = 217 plus fourteen for the magnitude bins.
  static const int acStatBins = 245;

  final JpegArithConditioning conditioning;

  final List<Uint8List> dcStats =
      List.generate(4, (_) => Uint8List(dcStatBins), growable: false);
  final List<Uint8List> acStats =
      List.generate(4, (_) => Uint8List(acStatBins), growable: false);

  /// DC predictions and conditioning categories, one per component in the scan.
  final Int32List lastDcValue = Int32List(4);
  final Int32List dcContext = Int32List(4);

  late JpegArithmeticDecoder coder;

  JpegArithmeticEntropy(this.conditioning);

  /// True when a decoded magnitude ran past the 15 categories the models
  /// define, which only corrupt data can do. Decoding stops rather than
  /// looping on a stream that will never terminate (T.81 F.2.4.4 b).
  bool corrupt = false;

  /// Starts an entropy-coded segment at [offset] of [data].
  void start(Uint8List data, int offset) {
    coder = JpegArithmeticDecoder(data, offset);
    corrupt = false;
  }

  /// Where marker parsing resumes after the segment.
  int get position => coder.position;

  void resetDcStats(int table) => dcStats[table].fillRange(0, dcStatBins, 0);

  void resetAcStats(int table) => acStats[table].fillRange(0, acStatBins, 0);

  /// Resets the predictions and conditioning of every component in the scan,
  /// which T.81 F.1.4.4.1.5 requires at a scan start and at every restart.
  void resetPredictions() {
    lastDcValue.fillRange(0, 4, 0);
    dcContext.fillRange(0, 4, 0);
  }

  int _decode(Uint8List stats, int at) => coder.decode(stats, at);

  /// The conditioning category of a difference whose magnitude leading bit is
  /// [m] and whose sign is [sign], per F.1.4.4.1.2: 0 for zero, 1 for small
  /// positive, 2 for small negative, 3 for large positive, 4 for large
  /// negative.
  int _category(int table, int m, int sign) {
    if (m < ((1 << conditioning.dcL[table]) >> 1)) return 0;
    if (m > ((1 << conditioning.dcU[table]) >> 1)) return 3 + sign;
    return 1 + sign;
  }

  /// Decodes one DC difference and updates the prediction of component [ci],
  /// per F.2.4.1 and Table F.4. Returns the new prediction.
  int decodeDcDifference(int ci, int table) {
    final stats = dcStats[table];
    final s0 = dcContext[ci];
    if (_decode(stats, s0) == 0) {
      dcContext[ci] = 0;
      return lastDcValue[ci];
    }
    final sign = _decode(stats, s0 + 1);
    final at = s0 + 2 + sign;

    // Figure F.23 with the magnitude category split out so the conditioning
    // category, which depends on the leading bit only, can be read off it.
    var m = _decode(stats, at);
    var context = at;
    if (m != 0) {
      context = 20; // Table F.4: X1 = 20.
      while (_decode(stats, context) != 0) {
        m <<= 1;
        if (m == 0x8000) {
          corrupt = true;
          return lastDcValue[ci];
        }
        context++;
      }
    }
    dcContext[ci] = 4 * _category(table, m, sign);

    var value = m;
    context += 14;
    while ((m >>= 1) != 0) {
      if (_decode(stats, context) != 0) value |= m;
    }
    value += 1;
    if (sign != 0) value = -value;

    // The difference accumulates modulo 2^16 in two's complement, which is the
    // precision T.81 defines for a DC coefficient.
    var prediction = (lastDcValue[ci] + value) & 0xFFFF;
    if (prediction >= 0x8000) prediction -= 0x10000;
    lastDcValue[ci] = prediction;
    return prediction;
  }

  /// Decodes the AC coefficients of one block into [block], which is in
  /// natural order and must start out zero. Follows Figure F.20.
  ///
  /// [naturalOrder] maps a zig-zag index to a position in [block].
  void decodeAcCoefficients(int table, Int32List block, int base, int ss,
      int se, int al, List<int> naturalOrder) {
    final stats = acStats[table];
    final kx = conditioning.acKx[table];
    var k = ss;
    while (k <= se) {
      var at = 3 * (k - 1);
      if (_decode(stats, at) != 0) return; // End of band.
      while (_decode(stats, at + 1) == 0) {
        at += 3;
        k++;
        if (k > se) {
          corrupt = true;
          return;
        }
      }
      // Table F.5: the sign uses the fixed 0.5 estimate.
      final sign = coder.decodeFixed();
      at += 2;

      // The first two magnitude decisions share the S0 + 1 bin; only from the
      // third does the AC_Context(K) split apply.
      var m = _decode(stats, at);
      var context = at;
      if (m != 0) {
        if (_decode(stats, at) != 0) {
          m <<= 1;
          context = k <= kx ? 189 : 217;
          while (_decode(stats, context) != 0) {
            m <<= 1;
            if (m == 0x8000) {
              corrupt = true;
              return;
            }
            context++;
          }
        }
      }
      var value = m;
      context += 14;
      while ((m >>= 1) != 0) {
        if (_decode(stats, context) != 0) value |= m;
      }
      value += 1;
      if (sign != 0) value = -value;
      block[base + naturalOrder[k]] = value << al;
      k++;
    }
  }

  /// The correction bit of a DC successive-approximation refinement scan,
  /// coded with the fixed estimate per G.1.3.1.
  int decodeCorrectionBit() => coder.decodeFixed();

  /// Refines the AC band of one block, per G.1.3.3 and Table G.2.
  void refineAcCoefficients(int table, Int32List block, int base, int ss,
      int se, int al, List<int> naturalOrder) {
    final stats = acStats[table];
    final positive = 1 << al;
    final negative = -positive;

    // EOBx: the end-of-band index the previous scan left behind. Above it the
    // stream carries an end-of-band decision, below it none.
    var eobx = se;
    while (eobx > 0 && block[base + naturalOrder[eobx]] == 0) {
      eobx--;
    }

    var k = ss;
    while (k <= se) {
      var at = 3 * (k - 1);
      if (k > eobx && _decode(stats, at) != 0) return;
      while (true) {
        final index = base + naturalOrder[k];
        if (block[index] != 0) {
          if (_decode(stats, at + 2) != 0) {
            block[index] += block[index] < 0 ? negative : positive;
          }
          break;
        }
        if (_decode(stats, at + 1) != 0) {
          block[index] = coder.decodeFixed() != 0 ? negative : positive;
          break;
        }
        at += 3;
        k++;
        if (k > se) {
          corrupt = true;
          return;
        }
      }
      k++;
    }
  }

  /// Decodes one lossless prediction difference, per H.1.2.3 and Table H.3.
  ///
  /// [aboveCategory] and [leftCategory] are the conditioning categories of the
  /// differences already decoded for the sample above and to the left, in the
  /// 0..4 encoding of [_category]. The category of this difference is left in
  /// [lastLosslessCategory].
  int decodeLosslessDifference(int table, int leftCategory, int aboveCategory) {
    final stats = dcStats[table];
    // Figure H.2: the 5 x 5 conditioning array.
    final s0 = 20 * leftCategory + 4 * aboveCategory;
    if (_decode(stats, s0) == 0) {
      lastLosslessCategory = 0;
      return 0;
    }
    final sign = _decode(stats, s0 + 1);
    final at = s0 + 2 + sign;
    // X1_Context(Db): 100 unless the difference above was large.
    final x1 = aboveCategory >= 3 ? 129 : 100;

    var m = _decode(stats, at);
    var context = at;
    if (m != 0) {
      context = x1;
      while (_decode(stats, context) != 0) {
        m <<= 1;
        if (m == 0x8000) {
          corrupt = true;
          lastLosslessCategory = 0;
          return 0;
        }
        context++;
      }
    }
    lastLosslessCategory = _category(table, m, sign);

    var value = m;
    context += 14;
    while ((m >>= 1) != 0) {
      if (_decode(stats, context) != 0) value |= m;
    }
    value += 1;
    if (sign != 0) value = -value;
    return value;
  }

  /// The conditioning category of the difference [decodeLosslessDifference]
  /// last returned.
  int lastLosslessCategory = 0;
}
