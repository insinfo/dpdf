import 'dart:typed_data';

/// Encodes data in the CCITT G4 FAX format.
///
/// This encoder is used for compressing bi-level (black and white) images
/// using the ITU-T T.6 (CCITT Group 4) facsimile compression.
class CCITTG4Encoder {
  final int _rowpixels;
  final int _rowbytes;
  int _bit = 8;
  int _data = 0;
  late Uint8List _refline;
  final BytesBuilder _outBuf = BytesBuilder();
  late Uint8List _dataBp;
  int _offsetData = 0;
  int _sizeData = 0;

  // Code table constants
  static const int _length = 0;
  static const int _code = 1;
  static const int _runlen = 2;
  static const int _eol = 0x001;
  static const int _g3CodeEol = -1;
  static const int _g3CodeInvalid = -2;

  /// Creates a new encoder.
  CCITTG4Encoder(int width)
      : _rowpixels = width,
        _rowbytes = (width + 7) ~/ 8 {
    _refline = Uint8List(_rowbytes);
  }

  /// Encodes a full image.
  static Uint8List compress(Uint8List data, int width, int height) {
    final g4 = CCITTG4Encoder(width);
    g4.fax4Encode(data, 0, g4._rowbytes * height);
    return g4.close();
  }

  /// Encodes a number of lines.
  void fax4Encode(Uint8List data, int offset, int size) {
    _dataBp = data;
    _offsetData = offset;
    _sizeData = size;
    while (_sizeData > 0) {
      _fax3Encode2DRow();
      for (int i = 0; i < _rowbytes; i++) {
        _refline[i] = _dataBp[_offsetData + i];
      }
      _offsetData += _rowbytes;
      _sizeData -= _rowbytes;
    }
  }

  /// Encodes a number of lines.
  void fax4EncodeHeight(Uint8List data, int height) {
    fax4Encode(data, 0, _rowbytes * height);
  }

  /// Closes the encoder and returns the encoded data.
  Uint8List close() {
    _fax4PostEncode();
    return _outBuf.toBytes();
  }

  void _putcode(List<int> table) {
    _putBits(table[_code], table[_length]);
  }

  void _putspan(int span, List<List<int>> tab) {
    int code, length;
    while (span >= 2624) {
      final te = tab[63 + (2560 >> 6)];
      code = te[_code];
      length = te[_length];
      _putBits(code, length);
      span -= te[_runlen];
    }
    if (span >= 64) {
      final te = tab[63 + (span >> 6)];
      code = te[_code];
      length = te[_length];
      _putBits(code, length);
      span -= te[_runlen];
    }
    code = tab[span][_code];
    length = tab[span][_length];
    _putBits(code, length);
  }

  void _putBits(int bits, int length) {
    while (length > _bit) {
      _data |= bits >> (length - _bit);
      length -= _bit;
      _outBuf.addByte(_data & 0xFF);
      _data = 0;
      _bit = 8;
    }
    _data |= (bits & _msbmask[length]) << (_bit - length);
    _bit -= length;
    if (_bit == 0) {
      _outBuf.addByte(_data & 0xFF);
      _data = 0;
      _bit = 8;
    }
  }

  void _fax3Encode2DRow() {
    int a0 = 0;
    int a1 = (_pixel(_dataBp, _offsetData, 0) != 0
        ? 0
        : _finddiff(_dataBp, _offsetData, 0, _rowpixels, 0));
    int b1 = (_pixel(_refline, 0, 0) != 0
        ? 0
        : _finddiff(_refline, 0, 0, _rowpixels, 0));

    for (;;) {
      int b2 = _finddiff2(_refline, 0, b1, _rowpixels, _pixel(_refline, 0, b1));
      if (b2 >= a1) {
        int d = b1 - a1;
        if (!(-3 <= d && d <= 3)) {
          // horizontal mode
          int a2 = _finddiff2(_dataBp, _offsetData, a1, _rowpixels,
              _pixel(_dataBp, _offsetData, a1));
          _putcode(_horizcode);
          if (a0 + a1 == 0 || _pixel(_dataBp, _offsetData, a0) == 0) {
            _putspan(a1 - a0, _tiffFaxWhiteCodes);
            _putspan(a2 - a1, _tiffFaxBlackCodes);
          } else {
            _putspan(a1 - a0, _tiffFaxBlackCodes);
            _putspan(a2 - a1, _tiffFaxWhiteCodes);
          }
          a0 = a2;
        } else {
          // vertical mode
          _putcode(_vcodes[d + 3]);
          a0 = a1;
        }
      } else {
        // pass mode
        _putcode(_passcode);
        a0 = b2;
      }
      if (a0 >= _rowpixels) break;
      a1 = _finddiff(_dataBp, _offsetData, a0, _rowpixels,
          _pixel(_dataBp, _offsetData, a0));
      b1 = _finddiff(
          _refline, 0, a0, _rowpixels, _pixel(_dataBp, _offsetData, a0) ^ 1);
      b1 = _finddiff(
          _refline, 0, b1, _rowpixels, _pixel(_dataBp, _offsetData, a0));
    }
  }

  void _fax4PostEncode() {
    _putBits(_eol, 12);
    _putBits(_eol, 12);
    if (_bit != 8) {
      _outBuf.addByte(_data & 0xFF);
      _data = 0;
      _bit = 8;
    }
  }

  int _pixel(Uint8List data, int offset, int bit) {
    if (bit >= _rowpixels) return 0;
    return ((data[offset + (bit >> 3)] & 0xff) >> (7 - (bit & 7))) & 1;
  }

  static int _find1span(Uint8List bp, int offset, int bs, int be) {
    int bits = be - bs;
    int span;
    int pos = offset + (bs >> 3);
    int n;

    if (bits > 0 && (n = (bs & 7)) != 0) {
      span = _oneruns[(bp[pos] << n) & 0xff];
      if (span > 8 - n) span = 8 - n;
      if (span > bits) span = bits;
      if (n + span < 8) return span;
      bits -= span;
      pos++;
    } else {
      span = 0;
    }

    while (bits >= 8) {
      if (bp[pos] != 0xff) {
        return span + _oneruns[bp[pos] & 0xff];
      }
      span += 8;
      bits -= 8;
      pos++;
    }

    if (bits > 0) {
      n = _oneruns[bp[pos] & 0xff];
      span += (n > bits ? bits : n);
    }
    return span;
  }

  static int _find0span(Uint8List bp, int offset, int bs, int be) {
    int bits = be - bs;
    int span;
    int pos = offset + (bs >> 3);
    int n;

    if (bits > 0 && (n = (bs & 7)) != 0) {
      span = _zeroruns[(bp[pos] << n) & 0xff];
      if (span > 8 - n) span = 8 - n;
      if (span > bits) span = bits;
      if (n + span < 8) return span;
      bits -= span;
      pos++;
    } else {
      span = 0;
    }

    while (bits >= 8) {
      if (bp[pos] != 0) {
        return span + _zeroruns[bp[pos] & 0xff];
      }
      span += 8;
      bits -= 8;
      pos++;
    }

    if (bits > 0) {
      n = _zeroruns[bp[pos] & 0xff];
      span += (n > bits ? bits : n);
    }
    return span;
  }

  static int _finddiff(Uint8List bp, int offset, int bs, int be, int color) {
    return bs +
        (color != 0
            ? _find1span(bp, offset, bs, be)
            : _find0span(bp, offset, bs, be));
  }

  static int _finddiff2(Uint8List bp, int offset, int bs, int be, int color) {
    return bs < be ? _finddiff(bp, offset, bs, be, color) : be;
  }

  // Run length tables
  static final List<int> _zeroruns = [
    8,
    7,
    6,
    6,
    5,
    5,
    5,
    5,
    4,
    4,
    4,
    4,
    4,
    4,
    4,
    4,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];

  static final List<int> _oneruns = [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
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
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    3,
    4,
    4,
    4,
    4,
    4,
    4,
    4,
    4,
    5,
    5,
    5,
    5,
    6,
    6,
    7,
    8,
  ];

  final List<int> _msbmask = [
    0x00,
    0x01,
    0x03,
    0x07,
    0x0f,
    0x1f,
    0x3f,
    0x7f,
    0xff
  ];

  final List<int> _horizcode = [3, 0x1, 0];
  final List<int> _passcode = [4, 0x1, 0];

  final List<List<int>> _vcodes = [
    [7, 0x03, 0],
    [6, 0x03, 0],
    [3, 0x03, 0],
    [1, 0x1, 0],
    [3, 0x2, 0],
    [6, 0x02, 0],
    [7, 0x02, 0]
  ];

  // White and black Huffman codes (abbreviated for brevity - full tables in production)
  final List<List<int>> _tiffFaxWhiteCodes = [
    [8, 0x35, 0],
    [6, 0x7, 1],
    [4, 0x7, 2],
    [4, 0x8, 3],
    [4, 0xB, 4],
    [4, 0xC, 5],
    [4, 0xE, 6],
    [4, 0xF, 7],
    [5, 0x13, 8],
    [5, 0x14, 9],
    [5, 0x7, 10],
    [5, 0x8, 11],
    [6, 0x8, 12],
    [6, 0x3, 13],
    [6, 0x34, 14],
    [6, 0x35, 15],
    [6, 0x2A, 16],
    [6, 0x2B, 17],
    [7, 0x27, 18],
    [7, 0xC, 19],
    [7, 0x8, 20],
    [7, 0x17, 21],
    [7, 0x3, 22],
    [7, 0x4, 23],
    [7, 0x28, 24],
    [7, 0x2B, 25],
    [7, 0x13, 26],
    [7, 0x24, 27],
    [7, 0x18, 28],
    [8, 0x2, 29],
    [8, 0x3, 30],
    [8, 0x1A, 31],
    [8, 0x1B, 32],
    [8, 0x12, 33],
    [8, 0x13, 34],
    [8, 0x14, 35],
    [8, 0x15, 36],
    [8, 0x16, 37],
    [8, 0x17, 38],
    [8, 0x28, 39],
    [8, 0x29, 40],
    [8, 0x2A, 41],
    [8, 0x2B, 42],
    [8, 0x2C, 43],
    [8, 0x2D, 44],
    [8, 0x4, 45],
    [8, 0x5, 46],
    [8, 0xA, 47],
    [8, 0xB, 48],
    [8, 0x52, 49],
    [8, 0x53, 50],
    [8, 0x54, 51],
    [8, 0x55, 52],
    [8, 0x24, 53],
    [8, 0x25, 54],
    [8, 0x58, 55],
    [8, 0x59, 56],
    [8, 0x5A, 57],
    [8, 0x5B, 58],
    [8, 0x4A, 59],
    [8, 0x4B, 60],
    [8, 0x32, 61],
    [8, 0x33, 62],
    [8, 0x34, 63],
    [5, 0x1B, 64],
    [5, 0x12, 128],
    [6, 0x17, 192],
    [7, 0x37, 256],
    [8, 0x36, 320],
    [8, 0x37, 384],
    [8, 0x64, 448],
    [8, 0x65, 512],
    [8, 0x68, 576],
    [8, 0x67, 640],
    [9, 0xCC, 704],
    [9, 0xCD, 768],
    [9, 0xD2, 832],
    [9, 0xD3, 896],
    [9, 0xD4, 960],
    [9, 0xD5, 1024],
    [9, 0xD6, 1088],
    [9, 0xD7, 1152],
    [9, 0xD8, 1216],
    [9, 0xD9, 1280],
    [9, 0xDA, 1344],
    [9, 0xDB, 1408],
    [9, 0x98, 1472],
    [9, 0x99, 1536],
    [9, 0x9A, 1600],
    [6, 0x18, 1664],
    [9, 0x9B, 1728],
    [11, 0x8, 1792],
    [11, 0xC, 1856],
    [11, 0xD, 1920],
    [12, 0x12, 1984],
    [12, 0x13, 2048],
    [12, 0x14, 2112],
    [12, 0x15, 2176],
    [12, 0x16, 2240],
    [12, 0x17, 2304],
    [12, 0x1C, 2368],
    [12, 0x1D, 2432],
    [12, 0x1E, 2496],
    [12, 0x1F, 2560],
    [12, 0x1, _g3CodeEol],
    [9, 0x1, _g3CodeInvalid],
    [10, 0x1, _g3CodeInvalid],
    [11, 0x1, _g3CodeInvalid],
    [12, 0x0, _g3CodeInvalid]
  ];

  final List<List<int>> _tiffFaxBlackCodes = [
    [10, 0x37, 0],
    [3, 0x2, 1],
    [2, 0x3, 2],
    [2, 0x2, 3],
    [3, 0x3, 4],
    [4, 0x3, 5],
    [4, 0x2, 6],
    [5, 0x3, 7],
    [6, 0x5, 8],
    [6, 0x4, 9],
    [7, 0x4, 10],
    [7, 0x5, 11],
    [7, 0x7, 12],
    [8, 0x4, 13],
    [8, 0x7, 14],
    [9, 0x18, 15],
    [10, 0x17, 16],
    [10, 0x18, 17],
    [10, 0x8, 18],
    [11, 0x67, 19],
    [11, 0x68, 20],
    [11, 0x6C, 21],
    [11, 0x37, 22],
    [11, 0x28, 23],
    [11, 0x17, 24],
    [11, 0x18, 25],
    [12, 0xCA, 26],
    [12, 0xCB, 27],
    [12, 0xCC, 28],
    [12, 0xCD, 29],
    [12, 0x68, 30],
    [12, 0x69, 31],
    [12, 0x6A, 32],
    [12, 0x6B, 33],
    [12, 0xD2, 34],
    [12, 0xD3, 35],
    [12, 0xD4, 36],
    [12, 0xD5, 37],
    [12, 0xD6, 38],
    [12, 0xD7, 39],
    [12, 0x6C, 40],
    [12, 0x6D, 41],
    [12, 0xDA, 42],
    [12, 0xDB, 43],
    [12, 0x54, 44],
    [12, 0x55, 45],
    [12, 0x56, 46],
    [12, 0x57, 47],
    [12, 0x64, 48],
    [12, 0x65, 49],
    [12, 0x52, 50],
    [12, 0x53, 51],
    [12, 0x24, 52],
    [12, 0x37, 53],
    [12, 0x38, 54],
    [12, 0x27, 55],
    [12, 0x28, 56],
    [12, 0x58, 57],
    [12, 0x59, 58],
    [12, 0x2B, 59],
    [12, 0x2C, 60],
    [12, 0x5A, 61],
    [12, 0x66, 62],
    [12, 0x67, 63],
    [10, 0xF, 64],
    [12, 0xC8, 128],
    [12, 0xC9, 192],
    [12, 0x5B, 256],
    [12, 0x33, 320],
    [12, 0x34, 384],
    [12, 0x35, 448],
    [13, 0x6C, 512],
    [13, 0x6D, 576],
    [13, 0x4A, 640],
    [13, 0x4B, 704],
    [13, 0x4C, 768],
    [13, 0x4D, 832],
    [13, 0x72, 896],
    [13, 0x73, 960],
    [13, 0x74, 1024],
    [13, 0x75, 1088],
    [13, 0x76, 1152],
    [13, 0x77, 1216],
    [13, 0x52, 1280],
    [13, 0x53, 1344],
    [13, 0x54, 1408],
    [13, 0x55, 1472],
    [13, 0x5A, 1536],
    [13, 0x5B, 1600],
    [13, 0x64, 1664],
    [13, 0x65, 1728],
    [11, 0x8, 1792],
    [11, 0xC, 1856],
    [11, 0xD, 1920],
    [12, 0x12, 1984],
    [12, 0x13, 2048],
    [12, 0x14, 2112],
    [12, 0x15, 2176],
    [12, 0x16, 2240],
    [12, 0x17, 2304],
    [12, 0x1C, 2368],
    [12, 0x1D, 2432],
    [12, 0x1E, 2496],
    [12, 0x1F, 2560],
    [12, 0x1, _g3CodeEol],
    [9, 0x1, _g3CodeInvalid],
    [10, 0x1, _g3CodeInvalid],
    [11, 0x1, _g3CodeInvalid],
    [12, 0x0, _g3CodeInvalid]
  ];
}
