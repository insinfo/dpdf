import 'dart:typed_data';
import '../exceptions/io_exception.dart';
import '../exceptions/io_exception_message_constant.dart';

/// Decodes TIFF FAX compressed data (CCITT Group 3 and Group 4).
class TIFFFaxDecoder {
  int _bitPointer = 0;
  int _bytePointer = 0;
  Uint8List? _data;
  final int _w;
  final int _h;
  final int _fillOrder;

  int _changingElemSize = 0;
  late List<int> _prevChangingElems;
  late List<int> _currChangingElems;
  int _lastChangingElement = 0;
  // int _compression = 2; // Unused
  // int _uncompressedMode = 0; // Unused
  int _fillBits = 0;
  int _oneD = 0;

  int fails = 0;

  /// Number of scan lines the last decode call actually produced.
  ///
  /// A `/Rows` value of 0 leaves the height undetermined (ISO 32000-1,
  /// Table 11), so the caller allocates an upper bound and trims to this.
  int rowsDecoded = 0;

  /// Indices of the scan lines whose decoding reported an error.
  ///
  /// This backs `/DamagedRowsBeforeError`, which tolerates a bounded number of
  /// damaged rows by substituting the previous row's pixels.
  final List<int> damagedRows = <int>[];
  // int _lineBitNum = 0; // Unused

  bool recoverFromImageError = false;

  void setRecoverFromImageError(bool r) {
    recoverFromImageError = r;
  }

  /// Table for flipping bytes when fillOrder = 2.
  static final Uint8List flipTable = Uint8List.fromList([
    0x00,
    0x80,
    0x40,
    0xc0,
    0x20,
    0xa0,
    0x60,
    0xe0,
    0x10,
    0x90,
    0x50,
    0xd0,
    0x30,
    0xb0,
    0x70,
    0xf0,
    0x08,
    0x88,
    0x48,
    0xc8,
    0x28,
    0xa8,
    0x68,
    0xe8,
    0x18,
    0x98,
    0x58,
    0xd8,
    0x38,
    0xb8,
    0x78,
    0xf8,
    0x04,
    0x84,
    0x44,
    0xc4,
    0x24,
    0xa4,
    0x64,
    0xe4,
    0x14,
    0x94,
    0x54,
    0xd4,
    0x34,
    0xb4,
    0x74,
    0xf4,
    0x0c,
    0x8c,
    0x4c,
    0xcc,
    0x2c,
    0xac,
    0x6c,
    0xec,
    0x1c,
    0x9c,
    0x5c,
    0xdc,
    0x3c,
    0xbc,
    0x7c,
    0xfc,
    0x02,
    0x82,
    0x42,
    0xc2,
    0x22,
    0xa2,
    0x62,
    0xe2,
    0x12,
    0x92,
    0x52,
    0xd2,
    0x32,
    0xb2,
    0x72,
    0xf2,
    0x0a,
    0x8a,
    0x4a,
    0xca,
    0x2a,
    0xaa,
    0x6a,
    0xea,
    0x1a,
    0x9a,
    0x5a,
    0xda,
    0x3a,
    0xba,
    0x7a,
    0xfa,
    0x06,
    0x86,
    0x46,
    0xc6,
    0x26,
    0xa6,
    0x66,
    0xe6,
    0x16,
    0x96,
    0x56,
    0xd6,
    0x36,
    0xb6,
    0x76,
    0xf6,
    0x0e,
    0x8e,
    0x4e,
    0xce,
    0x2e,
    0xae,
    0x6e,
    0xee,
    0x1e,
    0x9e,
    0x5e,
    0xde,
    0x3e,
    0xbe,
    0x7e,
    0xfe,
    0x01,
    0x81,
    0x41,
    0xc1,
    0x21,
    0xa1,
    0x61,
    0xe1,
    0x11,
    0x91,
    0x51,
    0xd1,
    0x31,
    0xb1,
    0x71,
    0xf1,
    0x09,
    0x89,
    0x49,
    0xc9,
    0x29,
    0xa9,
    0x69,
    0xe9,
    0x19,
    0x99,
    0x59,
    0xd9,
    0x39,
    0xb9,
    0x79,
    0xf9,
    0x05,
    0x85,
    0x45,
    0xc5,
    0x25,
    0xa5,
    0x65,
    0xe5,
    0x15,
    0x95,
    0x55,
    0xd5,
    0x35,
    0xb5,
    0x75,
    0xf5,
    0x0d,
    0x8d,
    0x4d,
    0xcd,
    0x2d,
    0xad,
    0x6d,
    0xed,
    0x1d,
    0x9d,
    0x5d,
    0xdd,
    0x3d,
    0xbd,
    0x7d,
    0xfd,
    0x03,
    0x83,
    0x43,
    0xc3,
    0x23,
    0xa3,
    0x63,
    0xe3,
    0x13,
    0x93,
    0x53,
    0xd3,
    0x33,
    0xb3,
    0x73,
    0xf3,
    0x0b,
    0x8b,
    0x4b,
    0xcb,
    0x2b,
    0xab,
    0x6b,
    0xeb,
    0x1b,
    0x9b,
    0x5b,
    0xdb,
    0x3b,
    0xbb,
    0x7b,
    0xfb,
    0x07,
    0x87,
    0x47,
    0xc7,
    0x27,
    0xa7,
    0x67,
    0xe7,
    0x17,
    0x97,
    0x57,
    0xd7,
    0x37,
    0xb7,
    0x77,
    0xf7,
    0x0f,
    0x8f,
    0x4f,
    0xcf,
    0x2f,
    0xaf,
    0x6f,
    0xef,
    0x1f,
    0x9f,
    0x5f,
    0xdf,
    0x3f,
    0xbf,
    0x7f,
    0xff
  ]);






  static final List<int> _twoDCodes = List<int>.generate(128, (lookahead) {
    final word = lookahead.toRadixString(2).padLeft(7, '0');
    const modes = <String, int>{
      '1': 5,
      '011': 6,
      '010': 4,
      '001': 1,
      '0001': 0,
      '000011': 7,
      '000010': 3,
      '0000011': 8,
      '0000010': 2,
    };
    for (final entry in modes.entries) {
      if (word.startsWith(entry.key)) {
        return (entry.value << 3) | entry.key.length;
      }
    }
    return lookahead == 1 ? 88 : 80;
  }, growable: false);

  /// Creates a TIFFFaxDecoder.
  TIFFFaxDecoder(this._fillOrder, this._w, this._h) {
    _prevChangingElems = List<int>.filled(2 * _w, 0);
    _currChangingElems = List<int>.filled(2 * _w, 0);
  }

  /// Sets options for decoding.
  void setOptions(int compression, int tiffT4Options, int tiffT6Options) {
    // _compression = compression;
    _oneD = tiffT4Options & 0x01;
    // _uncompressedMode = (tiffT4Options & 0x02) >> 1;
    _fillBits = (tiffT4Options & 0x04) >> 2;
    // tiffT6Options are used locally in decodeT6 or passed down
  }

  /// Reverses the bits in each byte of the array.

  /// Decodes Group 4 compressed data.
  void decodeT6(Uint8List buffer, Uint8List compData, int startX, int height,
      int tiffT6Options) {
    _data = compData;
    // _compression = 4;
    _bitPointer = 0;
    _bytePointer = 0;
    fails = 0;

    int scanlineStride = (_w + 7) ~/ 8;
    int a0;
    int a1;
    int b1;
    int b2;
    int entry;
    int code;
    int bits;
    bool isWhite;
    int currIndex;
    List<int> temp;
    // Return values from getNextChangingElement
    final b = List<int>.filled(2, 0);

    // uncompressedMode = (tiffT6Options & 0x02) >> 1;
    _fillBits = (tiffT6Options & 0x04) >> 2;

    // Local cached reference
    var cce = _currChangingElems;

    // Assume invisible preceding row of all white pixels
    _changingElemSize = 0;
    cce[_changingElemSize++] = _w;
    cce[_changingElemSize++] = _w;

    int lineOffset = 0;
    int bitOffset;
    rowsDecoded = 0;
    damagedRows.clear();

    for (int lines = 0; lines < height; lines++) {
      if (lines > 0 && _bytePointer >= _data!.length - 1) break;
      final int failsBefore = fails;
      final int bitsBefore = _bytePointer * 8 + _bitPointer;
      a0 = -1;
      isWhite = true;

      // Swap changing elements
      temp = _prevChangingElems;
      _prevChangingElems = _currChangingElems;
      _currChangingElems = temp;
      cce = _currChangingElems;
      currIndex = 0;

      bitOffset = startX;

      if (_fillBits == 1) {
        if (_bitPointer > 0) {
          int bitsLeft = 8 - _bitPointer;
          if (_nextNBits(bitsLeft) != 0) {
            throw IoException(IoExceptionMessageConstant
                .expectedTrailingZeroBitsForByteAlignedLines);
          }
        }
      }

      _lastChangingElement = 0;

      while (bitOffset < _w && _bytePointer < _data!.length - 1) {
        _getNextChangingElement(a0, isWhite, b);
        b1 = b[0];
        b2 = b[1];

        entry = _nextLesserThan8Bits(7);
        entry = _twoDCodes[entry] & 0xff;
        code = (entry & 0x78) >> 3;
        bits = entry & 0x07;

        if (code == 0) {
          // Pass
          if (!isWhite) {
            _setToBlack(buffer, lineOffset, bitOffset, b2 - bitOffset);
          }
          bitOffset = a0 = b2;
          _updatePointer(7 - bits);
        } else {
          if (code == 1) {
            // Horizontal
            _updatePointer(7 - bits);
            int number;
            if (isWhite) {
              number = _decodeWhiteCodeWord();
              bitOffset += number;
              cce[currIndex++] = bitOffset;
              number = _decodeBlackCodeWord();
              _setToBlack(buffer, lineOffset, bitOffset, number);
              bitOffset += number;
              cce[currIndex++] = bitOffset;
            } else {
              number = _decodeBlackCodeWord();
              _setToBlack(buffer, lineOffset, bitOffset, number);
              bitOffset += number;
              cce[currIndex++] = bitOffset;
              number = _decodeWhiteCodeWord();
              bitOffset += number;
              cce[currIndex++] = bitOffset;
            }
            a0 = bitOffset;
          } else {
            // Vertical
            if (code <= 8) {
              a1 = b1 + (code - 5);
              cce[currIndex++] = a1;
              if (!isWhite) {
                _setToBlack(buffer, lineOffset, bitOffset, a1 - bitOffset);
              }
              bitOffset = a0 = a1;
              isWhite = !isWhite;
              _updatePointer(7 - bits);
            } else {
              if (code == 11) {
                if (_nextLesserThan8Bits(3) != 7) {
                  throw IoException(IoExceptionMessageConstant
                      .invalidCodeEncounteredWhileDecoding2dGroup4CompressedData);
                }
                // Uncompressed extension words encode a white run followed
                // by one black sample, or an exit and the next coding color.
                while (true) {
                  var whiteRun = 0;
                  while (_nextLesserThan8Bits(1) == 0) {
                    whiteRun++;
                    if (whiteRun > _w - bitOffset + 6) {
                      throw IoException(
                          'Fax literal run exceeds the scanline.');
                    }
                  }
                  final leaving = whiteRun >= 6;
                  final whites = leaving ? whiteRun - 6 : whiteRun;
                  if (whites > 0) {
                    if (!isWhite) cce[currIndex++] = bitOffset;
                    isWhite = true;
                    bitOffset += whites;
                  }
                  if (leaving) {
                    final nextWhite = _nextLesserThan8Bits(1) == 0;
                    if (isWhite != nextWhite) cce[currIndex++] = bitOffset;
                    isWhite = nextWhite;
                    break;
                  }
                  if (whiteRun < 5) {
                    if (bitOffset >= _w) {
                      throw IoException(
                          'Fax literal pixel exceeds the scanline.');
                    }
                    if (isWhite) cce[currIndex++] = bitOffset;
                    _setToBlack(buffer, lineOffset, bitOffset++, 1);
                    isWhite = false;
                  }
                }
              } else {
                bitOffset = _w;
                _updatePointer(7 - bits);
              }
            }
          }
        }
      }

      if (currIndex < cce.length) {
        cce[currIndex++] = bitOffset;
      }
      // A line that consumed no bits is not a line: the data ran out, either
      // at the EOFB of 4.2.1.4 or because the stream is truncated. The check
      // has to be on bits consumed rather than on pixels produced, because a
      // pass code read out of trailing zeroes carries bitOffset to the end of
      // the row while reading nothing. Stopping here is what keeps an absent
      // /Rows from turning the rest of the buffer into invented blank lines.
      if (_bytePointer * 8 + _bitPointer <= bitsBefore) break;

      _changingElemSize = currIndex;
      lineOffset += scanlineStride;
      if (fails > failsBefore) damagedRows.add(lines);
      rowsDecoded = lines + 1;
    }
  }

  void _getNextChangingElement(int a0, bool isWhite, List<int> b) {
    // 4.2.1.3.1: b1 is the first changing element on the reference line to the
    // right of a0 and of opposite colour to a0's own colour. Changing elements
    // alternate, so an even index changes to black and an odd index changes to
    // white, and the search has to start on the matching parity.
    //
    // The scan resumes one element before the last hit, never at it: rounding
    // the resume point up to an even index skips the odd element just behind
    // it, and then b1 lands on the end of the line instead of the transition
    // that is really there. That misses only when the previous lookup was for
    // the opposite colour, which is why plain images decode and detailed ones
    // drift.
    var start = _lastChangingElement > 0 ? _lastChangingElement - 1 : 0;
    if (isWhite) {
      start &= ~0x1;
    } else {
      start |= 0x1;
    }

    final pce = _prevChangingElems;

    for (int i = start; i < _changingElemSize; i++) {
      if (pce[i] > a0) {
        if (isWhite && (i & 1) == 1) {
          continue;
        }
        if (!isWhite && (i & 1) == 0) {
          continue;
        }

        _lastChangingElement = i;
        b[0] = pce[i];

        if (i + 1 < _changingElemSize) {
          b[1] = pce[i + 1];
        } else {
          b[1] = _w + 1000;
        }
        return;
      }
    }
    b[0] = _w;
    b[1] = _w;
  }

  void _setToBlack(
      Uint8List buffer, int lineOffset, int bitOffset, int numBits) {
    // A run cannot be negative. A reference line that disagrees with the
    // coding line can still ask for one, and painting it would shift the whole
    // rest of the image, so drop it and let the caller's error accounting
    // report the line.
    if (numBits <= 0) return;
    final begin = lineOffset * 8 + bitOffset;
    final limit = begin + numBits;
    for (var byte = begin ~/ 8; byte * 8 < limit; byte++) {
      final first = begin > byte * 8 ? begin - byte * 8 : 0;
      final last = limit < (byte + 1) * 8 ? limit - byte * 8 : 8;
      if (byte < buffer.length) {
        buffer[byte] |= ((1 << (last - first)) - 1) << (8 - last);
      }
    }
  }

  int _nextNBits(int bitsToGet) {
    int b, next, next2;
    int l = _data!.length - 1;
    int bp = _bytePointer;

    if (_fillOrder == 2) {
      b = flipTable[_data![bp] & 0xFF];
      if (bp == l) {
        next = 0;
        next2 = 0;
      } else if ((bp + 1) == l) {
        next = flipTable[_data![bp + 1] & 0xFF];
        next2 = 0;
      } else {
        next = flipTable[_data![bp + 1] & 0xFF];
        next2 = flipTable[_data![bp + 2] & 0xFF];
      }
    } else {
      b = _data![bp] & 0xFF;
      if (bp == l) {
        next = 0;
        next2 = 0;
      } else if ((bp + 1) == l) {
        next = _data![bp + 1] & 0xFF;
        next2 = 0;
      } else {
        next = _data![bp + 1] & 0xFF;
        next2 = _data![bp + 2] & 0xFF;
      }
    }

    int val = (b << 16) | (next << 8) | next2;
    int shift = 24 - _bitPointer - bitsToGet;
    int result = (val >> shift) & ((1 << bitsToGet) - 1);

    _bitPointer += bitsToGet;
    if (_bitPointer >= 8) {
      _bytePointer += (_bitPointer >> 3);
      _bitPointer &= 7;
    }
    return result;
  }

  int _nextLesserThan8Bits(int bitsToGet) {
    int b, next;
    int l = _data!.length - 1;
    int bp = _bytePointer;

    if (_fillOrder == 2) {
      b = flipTable[_data![bp] & 0xFF];
      if (bp == l) {
        next = 0;
      } else {
        next = flipTable[_data![bp + 1] & 0xFF];
      }
    } else {
      b = _data![bp] & 0xFF;
      if (bp == l) {
        next = 0;
      } else {
        next = _data![bp + 1] & 0xFF;
      }
    }

    int val = (b << 8) | next;
    int shift = 16 - _bitPointer - bitsToGet;
    int result = (val >> shift) & ((1 << bitsToGet) - 1);

    _bitPointer += bitsToGet;
    if (_bitPointer >= 8) {
      _bytePointer++;
      _bitPointer &= 7;
    }
    return result;
  }

  void _updatePointer(int bitsToMoveBack) {
    _bitPointer -= bitsToMoveBack;
    while (_bitPointer < 0) {
      _bytePointer--;
      _bitPointer += 8;
    }
  }

  /// White run codes of ITU-T T.4: the terminating codes for runs 0..63 of
  /// Table 2, the makeup codes 64..1728 of Table 3, and the extended makeup
  /// codes 1792..2560 of Table 4 that both colours share. Each triple is
  /// (bit length, code, run length).
  ///
  /// These are the very codes `CCITTG4Encoder` writes, and the lookup the
  /// decoder uses is derived from them, so the two sides of a round trip
  /// cannot drift apart.
  static const List<List<int>> _whiteRunCodes = [
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
  ];

  /// Black run codes of ITU-T T.4, in the same (bit length, code, run length)
  /// form as [_whiteRunCodes].
  static const List<List<int>> _blackRunCodes = [
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
  ];

  /// Width of the window the run decoder peeks at. The longest code in either
  /// table is 13 bits, and `_nextNBits` can serve 13 bits from its three byte
  /// window at any bit position.
  static const int _runCodeBits = 13;

  static Int32List? _whiteRunLookup;
  static Int32List? _blackRunLookup;

  /// Expands a prefix code table into a flat lookup indexed by the next
  /// [_runCodeBits] bits.
  ///
  /// Every index whose leading bits match a code stores that code, so one
  /// array read resolves a run. The value packs the run length above the code
  /// length; zero means no code matches, which is how the 12 zero bits of an
  /// EOL stay distinguishable from a real code.
  static Int32List _buildRunLookup(List<List<int>> codes) {
    final table = Int32List(1 << _runCodeBits);
    for (final entry in codes) {
      final length = entry[0];
      final shift = _runCodeBits - length;
      final base = entry[1] << shift;
      final value = (entry[2] << 8) | length;
      for (var suffix = 0; suffix < (1 << shift); suffix++) {
        table[base | suffix] = value;
      }
    }
    return table;
  }

  /// Set when the last run decode stopped on an EOL or on bits no code
  /// matches, so the caller can end the line instead of looping on a run of
  /// zero that never advances.
  bool _runEndedLine = false;

  /// Decodes one run: zero or more makeup codes followed by one terminating
  /// code, which is what ITU-T T.4 4.1.3 calls a run length.
  int _decodeRunLength(Int32List lookup) {
    _runEndedLine = false;
    var total = 0;
    while (true) {
      final int window;
      try {
        window = _nextNBits(_runCodeBits);
      } on RangeError {
        _runEndedLine = true;
        return total;
      }
      // 000000000001 is the EOL of 4.1.2, and a run of fill bits precedes it.
      // Neither is a run code, and neither is an error.
      if (window == 0 || (window >> 1) == 1) {
        _updatePointer(_runCodeBits);
        _runEndedLine = true;
        return total;
      }
      final entry = lookup[window];
      if (entry == 0) {
        _updatePointer(_runCodeBits);
        _runEndedLine = true;
        fails++;
        return total;
      }
      _updatePointer(_runCodeBits - (entry & 0xFF));
      final run = entry >> 8;
      total += run;
      // Makeup codes are multiples of 64; only a terminating code of 0..63
      // closes the run.
      if (run < 64) return total;
    }
  }

  int _decodeWhiteCodeWord() =>
      _decodeRunLength(_whiteRunLookup ??= _buildRunLookup(_whiteRunCodes));

  int _decodeBlackCodeWord() =>
      _decodeRunLength(_blackRunLookup ??= _buildRunLookup(_blackRunCodes));

  /// Decodes a single scanline (1D).
  void _decodeNextScanline(Uint8List buffer, int lineOffset) {
    var isWhite = true;
    var bitOffset = 0;

    _changingElemSize = 0;
    final cce = _currChangingElems;

    // 4.1.3: a line is an alternating sequence of white and black runs that
    // starts white, and every run ends where the colour changes.
    while (bitOffset < _w) {
      final run =
          isWhite ? _decodeWhiteCodeWord() : _decodeBlackCodeWord();
      if (_runEndedLine) return;
      var painted = run;
      if (bitOffset + painted > _w) painted = _w - bitOffset;
      if (!isWhite && painted > 0) {
        _setToBlack(buffer, lineOffset, bitOffset, painted);
      }
      bitOffset += painted;
      if (_changingElemSize < cce.length) cce[_changingElemSize++] = bitOffset;
      isWhite = !isWhite;
    }
    if (_changingElemSize < cce.length) cce[_changingElemSize++] = bitOffset;
  }

  /// Decodes RLE.
  void decodeRLE(Uint8List buffer, Uint8List compData) {
    _data = compData;
    _bitPointer = 0;
    _bytePointer = 0;
    // _lineBitNum = 0;
    fails = 0;
    _prevChangingElems = List<int>.filled(_w + 1, 0);
    _currChangingElems = List<int>.filled(_w + 1, 0);

    int scanlineStride = (_w + 7) ~/ 8;
    int lineOffset = 0;
    rowsDecoded = 0;
    damagedRows.clear();

    for (int i = 0; i < _h; i++) {
      if (i > 0 && _bytePointer >= _data!.length) break;
      final int failsBefore = fails;
      _decodeNextScanline(buffer, lineOffset);
      if (fails > failsBefore) damagedRows.add(i);
      rowsDecoded = i + 1;
      if (_bitPointer != 0) {
        _bytePointer++;
        _bitPointer = 0;
      }
      // _lineBitNum += _w; // Should be bitsPerScanline?
      lineOffset += scanlineStride;
    }
  }

  /// Decodes Group 3 (T4).
  void decodeT4(Uint8List buffer, Uint8List compData) {
    _data = compData;
    _bitPointer = 0;
    _bytePointer = 0;
    // _lineBitNum = 0;
    fails = 0;
    _prevChangingElems = List<int>.filled(_w + 1, 0);
    _currChangingElems = List<int>.filled(_w + 1, 0);

    int scanlineStride = (_w + 7) ~/ 8;
    int lineOffset = 0;
    rowsDecoded = 0;
    damagedRows.clear();

    // EOL check
    if (_data!.length < 2) {
      // Error
      return;
    }

    // Check initial EOL
    // int next12 = _nextNBits(12);
    // if (next12 != 1) fails++; -- C# logic

    try {
      int next12 = _nextNBits(12);
      if (next12 != 1) fails++;
    } catch (e) {
      fails++;
    }
    _updatePointer(12);

    int modeFlag = 0;
    int lines = -1;

    try {
      while (modeFlag != 1) {
        modeFlag = _findNextLine();
        lines++;
      }
    } catch (e) {
      // failed finding line
    }

    _decodeNextScanline(buffer, lineOffset);
    lines++;
    // _lineBitNum += _w;
    lineOffset += scanlineStride;

    int a0, a1, b1, b2;
    // int b0 = 0;
    // int b_1 = 0;
    final b = List<int>.filled(2, 0);
    int entry, code, bits;
    bool isWhite;
    int currIndex;
    List<int> temp;

    while (lines < _h) {
      try {
        modeFlag = _findNextLine();
      } catch (e) {
        fails++;
        break;
      }

      if (modeFlag == 0) {
        // 2D
        temp = _prevChangingElems;
        _prevChangingElems = _currChangingElems;
        _currChangingElems = temp;
        final cce = _currChangingElems; // alias
        currIndex = 0;
        a0 = -1;
        isWhite = true;
        int bitOffset = 0;
        _lastChangingElement = 0;

        while (bitOffset < _w) {
          _getNextChangingElement(a0, isWhite, b);
          b1 = b[0];
          b2 = b[1];

          entry = _nextLesserThan8Bits(7);
          entry = _twoDCodes[entry] & 0xff;
          code = (entry & 0x78) >> 3;
          bits = entry & 0x07;

          if (code == 0) {
            // Pass
            if (!isWhite) {
              _setToBlack(buffer, lineOffset, bitOffset, b2 - bitOffset);
            }
            bitOffset = a0 = b2;
            _updatePointer(7 - bits);
          } else if (code == 1) {
            // Horizontal
            _updatePointer(7 - bits);
            int number;
            if (isWhite) {
              number = _decodeWhiteCodeWord();
              bitOffset += number;
              cce[currIndex++] = bitOffset;
              number = _decodeBlackCodeWord();
              _setToBlack(buffer, lineOffset, bitOffset, number);
              bitOffset += number;
              cce[currIndex++] = bitOffset;
            } else {
              number = _decodeBlackCodeWord();
              _setToBlack(buffer, lineOffset, bitOffset, number);
              bitOffset += number;
              cce[currIndex++] = bitOffset;
              number = _decodeWhiteCodeWord();
              bitOffset += number;
              cce[currIndex++] = bitOffset;
            }
            a0 = bitOffset;
          } else {
            // Vertical
            if (code <= 8) {
              a1 = b1 + (code - 5);
              cce[currIndex++] = a1;
              if (!isWhite) {
                _setToBlack(buffer, lineOffset, bitOffset, a1 - bitOffset);
              }
              bitOffset = a0 = a1;
              isWhite = !isWhite;
              _updatePointer(7 - bits);
            } else {
              fails++;
              break;
            }
          }
        }
        cce[currIndex++] = bitOffset;
        _changingElemSize = currIndex;
      } else {
        // 1D
        _decodeNextScanline(buffer, lineOffset);
      }

      lines++;
      lineOffset += scanlineStride;
    }
      // One scan line was written per advance of lineOffset, which is what the
    // caller trims an undetermined /Rows to.
    rowsDecoded = scanlineStride > 0 ? lineOffset ~/ scanlineStride : 0;
}

  int _findNextLine() {
    int bitIndexMax = (_data!.length * 8) - 1;
    int bitIndexMax12 = bitIndexMax - 12;
    int bitIndex = (_bytePointer * 8) + _bitPointer;

    while (bitIndex <= bitIndexMax12) {
      int next12 = _nextNBits(12);
      bitIndex += 12;
      while (next12 != 1 && bitIndex < bitIndexMax) {
        next12 = ((next12 & 0x7FF) << 1) | (_nextLesserThan8Bits(1) & 1);
        bitIndex++;
      }
      if (next12 == 1) {
        if (_oneD == 1) {
          if (bitIndex < bitIndexMax) {
            return _nextLesserThan8Bits(1);
          }
        } else {
          return 1;
        }
      }
    }
    throw IoException("EOL not found");
  }

  static void reverseBits(Uint8List b) {
    for (int i = 0; i < b.length; i++) {
      // C# FlipTable is 0-255 map.
      // flipTable is available as static final Uint8List in this class.
      b[i] = flipTable[b[i] & 0xff];
    }
  }

  /// Decodes 1D
  void decode1D(Uint8List buffer, Uint8List compData, int startX, int height) {
    _data = compData;
    _bitPointer = 0;
    _bytePointer = 0;
    // _compression = 2; // G3 1D

    int scanlineStride = (_w + 7) ~/ 8;
    int lineOffset = 0;
    rowsDecoded = 0;
    damagedRows.clear();

    for (int lines = 0; lines < height; lines++) {
      if (lines > 0 && _bytePointer >= _data!.length) break;
      final int failsBefore = fails;
      _decodeNextScanline(buffer, lineOffset);
      if (fails > failsBefore) damagedRows.add(lines);
      rowsDecoded = lines + 1;
      lineOffset += scanlineStride;
    }
  }

  /// Decodes 2D (G3)
  void decode2D(Uint8List buffer, Uint8List compData, int startX, int height,
      int tiffT4Options) {
    _data = compData;
    _bitPointer = 0;
    _bytePointer = 0;
    _fillBits = (tiffT4Options & 0x04) >> 2;
    _oneD = tiffT4Options & 0x01;

    int scanlineStride = (_w + 7) ~/ 8;
    int a0, a1, b1, b2;
    int entry, code, bits;
    bool isWhite;
    int currIndex;
    List<int> temp;
    final b = List<int>.filled(2, 0);

    // Initial invisible white line
    _changingElemSize = 0;
    _currChangingElems[0] = _w;
    _currChangingElems[1] = _w;
    _changingElemSize = 2;

    int lineOffset = 0;

    for (int lines = 0; lines < height; lines++) {
      bool is1D = true;
      try {
        int tag = _findNextLine();
        is1D = (tag == 1);
      } catch (e) {
        fails++;
        // On error, we might skip to next EOL?
        // For now, let's assume it's 1D if we can't find tag
      }

      if (is1D) {
        _decodeNextScanline(buffer, lineOffset);
      } else {
        // 2D line
        temp = _prevChangingElems;
        _prevChangingElems = _currChangingElems;
        _currChangingElems = temp;
        final cce = _currChangingElems;
        currIndex = 0;
        a0 = -1;
        isWhite = true;
        int bitOffset = startX;
        _lastChangingElement = 0;

        while (bitOffset < _w) {
          _getNextChangingElement(a0, isWhite, b);
          b1 = b[0];
          b2 = b[1];

          entry = _nextLesserThan8Bits(7);
          entry = _twoDCodes[entry] & 0xff;
          code = (entry & 0x78) >> 3;
          bits = entry & 0x07;

          if (code == 0) {
            // Pass
            if (!isWhite) {
              _setToBlack(buffer, lineOffset, bitOffset, b2 - bitOffset);
            }
            bitOffset = a0 = b2;
            _updatePointer(7 - bits);
          } else if (code == 1) {
            // Horizontal
            _updatePointer(7 - bits);
            int number;
            if (isWhite) {
              number = _decodeWhiteCodeWord();
              bitOffset += number;
              cce[currIndex++] = bitOffset;
              number = _decodeBlackCodeWord();
              _setToBlack(buffer, lineOffset, bitOffset, number);
              bitOffset += number;
              cce[currIndex++] = bitOffset;
            } else {
              number = _decodeBlackCodeWord();
              _setToBlack(buffer, lineOffset, bitOffset, number);
              bitOffset += number;
              cce[currIndex++] = bitOffset;
              number = _decodeWhiteCodeWord();
              bitOffset += number;
              cce[currIndex++] = bitOffset;
            }
            a0 = bitOffset;
          } else if (code <= 8) {
            // Vertical
            a1 = b1 + (code - 5);
            cce[currIndex++] = a1;
            if (!isWhite) {
              _setToBlack(buffer, lineOffset, bitOffset, a1 - bitOffset);
            }
            bitOffset = a0 = a1;
            isWhite = !isWhite;
            _updatePointer(7 - bits);
          } else {
            // Error
            fails++;
            _updatePointer(7 - bits);
            break;
          }
        }
        cce[currIndex++] = bitOffset;
        _changingElemSize = currIndex;
      }
      lineOffset += scanlineStride;
    }
  }
}
