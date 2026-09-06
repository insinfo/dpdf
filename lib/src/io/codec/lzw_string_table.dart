import 'dart:typed_data';
import '../../commons/utils/java_util.dart';

/// General purpose LZW String Table for compression and decompression.
///
/// This is a hash-based string table used in LZW compression.
/// Each entry represents a string made up of a predecessor string (by code)
/// and a character appended to it.
class LZWStringTable {
  // codesize + Reserved Codes
  static const int _resCodes = 2;

  // Hash free marker
  static const int _hashFree = -1;

  // Next first marker (no predecessor)
  static const int _nextFirst = -1;

  static const int _maxbits = 12;
  static const int _maxstr = 1 << _maxbits;
  static const int _hashsize = 9973;
  static const int _hashstep = 2039;

  /// After predecessor character
  final Uint8List _strChr;

  /// Predecessor string code
  final Int16List _strNxt;

  /// Hash table to find predecessor + char pairs
  final Int16List _strHsh;

  /// Length of each expanded code
  final Int32List _strLen;

  /// Next code if adding new prestring + char
  int _numStrings = 0;

  /// Creates a new LZWStringTable with preallocated memory.
  LZWStringTable()
      : _strChr = Uint8List(_maxstr),
        _strNxt = Int16List(_maxstr),
        _strLen = Int32List(_maxstr),
        _strHsh = Int16List(_hashsize);

  /// Adds a new character string to the table.
  ///
  /// [index] - Value of -1 indicates no predecessor (used in initialization)
  /// [b] - The byte (character) to add which follows the predecessor string
  ///
  /// Returns 0xFFFF if no space left, else returns the allocated code.
  int addCharString(int index, int b) {
    if (_numStrings >= _maxstr) {
      return 0xFFFF;
    }

    int hshidx = _hash(index, b);
    while (_strHsh[hshidx] != _hashFree) {
      hshidx = (hshidx + _hashstep) % _hashsize;
    }

    _strHsh[hshidx] = _numStrings;
    _strChr[_numStrings] = b;

    if (index == _hashFree) {
      _strNxt[_numStrings] = _nextFirst;
      _strLen[_numStrings] = 1;
    } else {
      _strNxt[_numStrings] = index;
      _strLen[_numStrings] = _strLen[index] + 1;
    }

    return _numStrings++;
  }

  /// Finds a character string in the table.
  ///
  /// [index] - Index to prefix string
  /// [b] - The character that follows the index prefix
  ///
  /// Returns b if index is -1, else returns the code for this prefix and byte.
  int findCharString(int index, int b) {
    if (index == _hashFree) {
      return b & 0xFF;
    }

    int hshidx = _hash(index, b);
    int nxtidx;

    while ((nxtidx = _strHsh[hshidx]) != _hashFree) {
      if (_strNxt[nxtidx] == index && _strChr[nxtidx] == b) {
        return nxtidx;
      }
      hshidx = (hshidx + _hashstep) % _hashsize;
    }

    return -1;
  }

  /// Clears the table and initializes with single-byte codes.
  ///
  /// [codesize] - The size of code to be preallocated.
  void clearTable(int codesize) {
    _numStrings = 0;
    for (int q = 0; q < _hashsize; q++) {
      _strHsh[q] = _hashFree;
    }

    int w = (1 << codesize) + _resCodes;
    for (int q = 0; q < w; q++) {
      addCharString(-1, q);
    }
  }

  /// Computes hash for finding or storing string codes.
  static int _hash(int index, int lastbyte) {
    return ((((lastbyte << 8) ^ index) & 0xFFFF) % _hashsize);
  }

  /// Expands a code into the output buffer.
  ///
  /// If expanded data doesn't fit into array, only what will fit is written.
  /// Returns the length of data expanded into buf. If the expanded code is longer
  /// than space left in buf, returns a negative number.
  int expandCode(Uint8List buf, int offset, int code, int skipHead) {
    if (offset == -2 && skipHead == 1) {
      skipHead = 0;
    }

    // code == -1 is checked just in case
    if (code == -1 || skipHead == _strLen[code]) {
      return 0;
    }

    // Length of expanded code left
    int codeLen = _strLen[code] - skipHead;
    // How much space left
    int bufSpace = buf.length - offset;
    // How much data we are actually expanding
    int expandLen = bufSpace > codeLen ? codeLen : bufSpace;

    // Only > 0 if codeLen > bufSpace [leftovers]
    int skipTail = codeLen - expandLen;

    // Initialize to exclusive end address of buffer area
    int idx = offset + expandLen;

    // Data unpacks in reverse direction
    while (idx > offset && code != -1) {
      if (--skipTail < 0) {
        buf[--idx] = _strChr[code];
      }
      code = _strNxt[code];
    }

    if (codeLen > expandLen) {
      return -expandLen; // Indicate what part of codeLen used
    }
    return expandLen; // Indicate length of data unpacked
  }

  /// Debug dump of string table.
  void dump(StringBuffer output) {
    for (int i = 258; i < _numStrings; ++i) {
      output.writeln(' strNxt_[$i] = ${_strNxt[i]} strChr_ '
          '${JavaUtil.integerToHexString(_strChr[i] & 0xFF)} strLen_ '
          '${JavaUtil.integerToHexString(_strLen[i])}');
    }
  }
}
