import 'dart:convert';
import 'dart:math';

import 'bit_vector.dart';
import 'block_pair.dart';
import 'byte_array.dart';
import 'byte_matrix.dart';
import 'character_set_eci.dart';
import 'encode_hint_type.dart';
import 'error_correction_level.dart';
import 'gf_256.dart';
import 'mask_util.dart';
import 'matrix_util.dart';
import 'mode.dart';
import 'qr_code.dart';
import 'reed_solomon_encoder.dart';
import 'version.dart';

class Encoder {
  // The original table is defined in the table 5 of JISX0510:2004 (p.19).
  static final List<int> _ALPHANUMERIC_TABLE = [
    // 0x00-0x0f
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    // 0x10-0x1f
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    // 0x20-0x2f
    36, -1, -1, -1, 37, 38, -1, -1, -1, -1, 39, 40, -1, 41, 42, 43,
    // 0x30-0x3f
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 44, -1, -1, -1, -1, -1,
    // 0x40-0x4f
    -1, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
    // 0x50-0x5f
    25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, -1, -1, -1, -1, -1
  ];

  static const String _DEFAULT_BYTE_MODE_ENCODING = "ISO-8859-1";

  // The mask penalty calculation is complicated.  See Table 21 of JISX0510:2004 (p.45) for details.
  // Basically it applies four rules and summate all penalties.
  static int _calculateMaskPenalty(ByteMatrix matrix) {
    int penalty = 0;
    penalty += MaskUtil.applyMaskPenaltyRule1(matrix);
    penalty += MaskUtil.applyMaskPenaltyRule2(matrix);
    penalty += MaskUtil.applyMaskPenaltyRule3(matrix);
    penalty += MaskUtil.applyMaskPenaltyRule4(matrix);
    return penalty;
  }

  /// Encode "bytes" with the error correction level "ecLevel".
  /// [content] - String to encode
  /// [ecLevel] - Error-correction level to use
  /// [hints] - Optional Map containing  encoding and suggested minimum version to use
  /// [qrCode] - QR code to store the result in
  static void encode(String content, ErrorCorrectionLevel ecLevel,
      Map<EncodeHintType, dynamic>? hints, QRCode qrCode) {
    String encoding =
        (hints != null && hints.containsKey(EncodeHintType.CHARACTER_SET))
            ? hints[EncodeHintType.CHARACTER_SET] as String
            : _DEFAULT_BYTE_MODE_ENCODING;

    int desiredMinVersion = 1;
    if (hints != null && hints.containsKey(EncodeHintType.MIN_VERSION_NR)) {
      desiredMinVersion = hints[EncodeHintType.MIN_VERSION_NR] as int;
    }

    //Check if desired level is within bounds of [1,40]
    if (desiredMinVersion < 1) {
      desiredMinVersion = 1;
    }
    if (desiredMinVersion > 40) {
      desiredMinVersion = 40;
    }
    // Step 1: Choose the mode (encoding).
    Mode mode = chooseMode(content, encoding);
    // Step 2: Append "bytes" into "dataBits" in appropriate encoding.
    BitVector dataBits = BitVector();
    appendBytes(content, mode, dataBits, encoding);
    // Step 3: Initialize QR code that can contain "dataBits".
    int numInputBytes = dataBits.sizeInBytes();
    _initQRCode(numInputBytes, ecLevel, desiredMinVersion, mode, qrCode);
    // Step 4: Build another bit vector that contains header and data.
    BitVector headerAndDataBits = BitVector();
    // Step 4.5: Append ECI message if applicable
    if (mode == Mode.BYTE && _DEFAULT_BYTE_MODE_ENCODING != encoding) {
      CharacterSetECI? eci = CharacterSetECI.getCharacterSetECIByName(encoding);
      if (eci != null) {
        _appendECI(eci, headerAndDataBits);
      }
    }
    _appendModeInfo(mode, headerAndDataBits);
    int numLetters =
        mode == Mode.BYTE ? dataBits.sizeInBytes() : content.length;
    _appendLengthInfo(numLetters, qrCode.getVersion(), mode, headerAndDataBits);
    headerAndDataBits.appendBitVector(dataBits);
    // Step 5: Terminate the bits properly.
    _terminateBits(qrCode.getNumDataBytes(), headerAndDataBits);
    // Step 6: Interleave data bits with error correction code.
    BitVector finalBits = BitVector();
    _interleaveWithECBytes(headerAndDataBits, qrCode.getNumTotalBytes(),
        qrCode.getNumDataBytes(), qrCode.getNumRSBlocks(), finalBits);
    // Step 7: Choose the mask pattern and set to "qrCode".
    ByteMatrix matrix =
        ByteMatrix(qrCode.getMatrixWidth(), qrCode.getMatrixWidth());
    qrCode.setMaskPattern(_chooseMaskPattern(
        finalBits, qrCode.getECLevel()!, qrCode.getVersion(), matrix));
    // Step 8.  Build the matrix and set it to "qrCode".
    MatrixUtil.buildMatrix(finalBits, qrCode.getECLevel()!, qrCode.getVersion(),
        qrCode.getMaskPattern(), matrix);
    qrCode.setMatrix(matrix);
    // Step 9.  Make sure we have a valid QR Code.
    if (!qrCode.isValid()) {
      throw Exception("Invalid QR code: $qrCode");
    }
  }

  static int getAlphanumericCode(int code) {
    if (code < _ALPHANUMERIC_TABLE.length) {
      return _ALPHANUMERIC_TABLE[code];
    }
    return -1;
  }

  static Mode chooseMode(String content, [String? encoding]) {
    if ("Shift_JIS" == encoding) {
      // Choose Kanji mode if all input are double-byte characters
      return _isOnlyDoubleByteKanji(content) ? Mode.KANJI : Mode.BYTE;
    }
    bool hasNumeric = false;
    bool hasAlphanumeric = false;
    for (int i = 0; i < content.length; ++i) {
      int c = content.codeUnitAt(i);
      if (c >= 48 && c <= 57) {
        // '0' - '9'
        hasNumeric = true;
      } else {
        if (getAlphanumericCode(c) != -1) {
          hasAlphanumeric = true;
        } else {
          return Mode.BYTE;
        }
      }
    }
    if (hasAlphanumeric) {
      return Mode.ALPHANUMERIC;
    } else {
      if (hasNumeric) {
        return Mode.NUMERIC;
      }
    }
    return Mode.BYTE;
  }

  static bool _isOnlyDoubleByteKanji(String content) {
    try {
      // Dart does not strictly support Shift_JIS natively without plugins.
      // Since this is a port, if we can't support it, we assume false or throw.
      // For now, assuming false as we cannot easily encode to Shift_JIS.
      return false;
    } catch (_) {
      return false;
    }
  }

  static int _chooseMaskPattern(BitVector bits, ErrorCorrectionLevel ecLevel,
      int version, ByteMatrix matrix) {
    // Lower penalty is better.
    int minPenalty = 0x7FFFFFFF;
    int bestMaskPattern = -1;
    // We try all mask patterns to choose the best one.
    for (int maskPattern = 0;
        maskPattern < QRCode.NUM_MASK_PATTERNS;
        maskPattern++) {
      MatrixUtil.buildMatrix(bits, ecLevel, version, maskPattern, matrix);
      int penalty = _calculateMaskPenalty(matrix);
      if (penalty < minPenalty) {
        minPenalty = penalty;
        bestMaskPattern = maskPattern;
      }
    }
    return bestMaskPattern;
  }

  static void _initQRCode(int numInputBytes, ErrorCorrectionLevel ecLevel,
      int desiredMinVersion, Mode mode, QRCode qrCode) {
    qrCode.setECLevel(ecLevel);
    qrCode.setMode(mode);
    // In the following comments, we use numbers of Version 7-H.
    for (int versionNum = desiredMinVersion; versionNum <= 40; versionNum++) {
      Version version = Version.getVersionForNumber(versionNum);
      // numBytes = 196
      int numBytes = version.getTotalCodewords();
      // getNumECBytes = 130
      ECBlocks ecBlocks = version.getECBlocksForLevel(ecLevel);
      int numEcBytes = ecBlocks.getTotalECCodewords();
      // getNumRSBlocks = 5
      int numRSBlocks = ecBlocks.getNumBlocks();
      // getNumDataBytes = 196 - 130 = 66
      int numDataBytes = numBytes - numEcBytes;
      // We want to choose the smallest version which can contain data of "numInputBytes" + some
      // extra bits for the header (mode info and length info). The header can be three bytes
      // (precisely 4 + 16 bits) at most. Hence we do +3 here.
      if (numDataBytes >= numInputBytes + 3) {
        // Yay, we found the proper rs block info!
        qrCode.setVersion(versionNum);
        qrCode.setNumTotalBytes(numBytes);
        qrCode.setNumDataBytes(numDataBytes);
        qrCode.setNumRSBlocks(numRSBlocks);
        // getNumECBytes = 196 - 66 = 130
        qrCode.setNumECBytes(numEcBytes);
        // matrix width = 21 + 6 * 4 = 45
        qrCode.setMatrixWidth(version.getDimensionForVersion());
        return;
      }
    }
    throw Exception(
        "Cannot find proper rs block info (input data too big?)"); // WriterException
  }

  static void _terminateBits(int numDataBytes, BitVector bits) {
    int capacity = numDataBytes << 3;
    if (bits.size() > capacity) {
      throw Exception(
          "data bits cannot fit in the QR Code ${bits.size()} > $capacity"); // WriterException
    }
    // Append termination bits. See 8.4.8 of JISX0510:2004 (p.24) for details.
    for (int i = 0; i < 4 && bits.size() < capacity; ++i) {
      bits.appendBit(0);
    }
    int numBitsInLastByte = bits.size() % 8;
    // If the last byte isn't 8-bit aligned, we'll add padding bits.
    if (numBitsInLastByte > 0) {
      int numPaddingBits = 8 - numBitsInLastByte;
      for (int i = 0; i < numPaddingBits; ++i) {
        bits.appendBit(0);
      }
    }
    // Should be 8-bit aligned here.
    if (bits.size() % 8 != 0) {
      throw Exception("Number of bits is not a multiple of 8");
    }
    // If we have more space, we'll fill the space with padding patterns defined in 8.4.9 (p.24).
    int numPaddingBytes = numDataBytes - bits.sizeInBytes();
    for (int i = 0; i < numPaddingBytes; ++i) {
      if (i % 2 == 0) {
        bits.appendBits(0xec, 8);
      } else {
        bits.appendBits(0x11, 8);
      }
    }
    if (bits.size() != capacity) {
      throw Exception("Bits size does not equal capacity");
    }
  }

  static void _getNumDataBytesAndNumECBytesForBlockID(
      int numTotalBytes,
      int numDataBytes,
      int numRSBlocks,
      int blockID,
      List<int> numDataBytesInBlock,
      List<int> numECBytesInBlock) {
    if (blockID >= numRSBlocks) {
      throw Exception("Block ID too large");
    }
    // numRsBlocksInGroup2 = 196 % 5 = 1
    int numRsBlocksInGroup2 = numTotalBytes % numRSBlocks;
    // numRsBlocksInGroup1 = 5 - 1 = 4
    int numRsBlocksInGroup1 = numRSBlocks - numRsBlocksInGroup2;
    // numTotalBytesInGroup1 = 196 / 5 = 39
    int numTotalBytesInGroup1 = numTotalBytes ~/ numRSBlocks;
    // numTotalBytesInGroup2 = 39 + 1 = 40
    int numTotalBytesInGroup2 = numTotalBytesInGroup1 + 1;
    // numDataBytesInGroup1 = 66 / 5 = 13
    int numDataBytesInGroup1 = numDataBytes ~/ numRSBlocks;
    // numDataBytesInGroup2 = 13 + 1 = 14
    int numDataBytesInGroup2 = numDataBytesInGroup1 + 1;
    // numEcBytesInGroup1 = 39 - 13 = 26
    int numEcBytesInGroup1 = numTotalBytesInGroup1 - numDataBytesInGroup1;
    // numEcBytesInGroup2 = 40 - 14 = 26
    int numEcBytesInGroup2 = numTotalBytesInGroup2 - numDataBytesInGroup2;
    // Sanity checks.
    // 26 = 26
    if (numEcBytesInGroup1 != numEcBytesInGroup2) {
      throw Exception("EC bytes mismatch");
    }
    // 5 = 4 + 1.
    if (numRSBlocks != numRsBlocksInGroup1 + numRsBlocksInGroup2) {
      throw Exception("RS blocks mismatch");
    }
    // 196 = (13 + 26) * 4 + (14 + 26) * 1
    if (numTotalBytes !=
        ((numDataBytesInGroup1 + numEcBytesInGroup1) * numRsBlocksInGroup1) +
            ((numDataBytesInGroup2 + numEcBytesInGroup2) *
                numRsBlocksInGroup2)) {
      throw Exception("Total bytes mismatch");
    }
    if (blockID < numRsBlocksInGroup1) {
      numDataBytesInBlock[0] = numDataBytesInGroup1;
      numECBytesInBlock[0] = numEcBytesInGroup1;
    } else {
      numDataBytesInBlock[0] = numDataBytesInGroup2;
      numECBytesInBlock[0] = numEcBytesInGroup2;
    }
  }

  static void _interleaveWithECBytes(BitVector bits, int numTotalBytes,
      int numDataBytes, int numRSBlocks, BitVector result) {
    // "bits" must have "getNumDataBytes" bytes of data.
    if (bits.sizeInBytes() != numDataBytes) {
      throw Exception("Number of bits and data bytes does not match");
    }
    // Step 1.  Divide data bytes into blocks and generate error correction bytes for them. We'll
    // store the divided data bytes blocks and error correction bytes blocks into "blocks".
    int dataBytesOffset = 0;
    int maxNumDataBytes = 0;
    int maxNumEcBytes = 0;
    // Since, we know the number of reedsolmon blocks, we can initialize the vector with the number.
    List<BlockPair> blocks = [];
    for (int i = 0; i < numRSBlocks; ++i) {
      List<int> numDataBytesInBlock = [0];
      List<int> numEcBytesInBlock = [0];
      _getNumDataBytesAndNumECBytesForBlockID(numTotalBytes, numDataBytes,
          numRSBlocks, i, numDataBytesInBlock, numEcBytesInBlock);
      ByteArray dataBytes = ByteArray(numDataBytesInBlock[0]);
      dataBytes.setRange(
          bits.getArray(), dataBytesOffset, numDataBytesInBlock[0]);
      ByteArray ecBytes = _generateECBytes(dataBytes, numEcBytesInBlock[0]);
      blocks.add(BlockPair(dataBytes, ecBytes));
      maxNumDataBytes = max(maxNumDataBytes, dataBytes.size());
      maxNumEcBytes = max(maxNumEcBytes, ecBytes.size());
      dataBytesOffset += numDataBytesInBlock[0];
    }
    if (numDataBytes != dataBytesOffset) {
      throw Exception("Data bytes does not match offset");
    }
    // First, place data blocks.
    for (int i = 0; i < maxNumDataBytes; ++i) {
      for (int j = 0; j < blocks.length; ++j) {
        ByteArray dataBytes = blocks[j].getDataBytes();
        if (i < dataBytes.size()) {
          result.appendBits(dataBytes.at(i), 8);
        }
      }
    }
    // Then, place error correction blocks.
    for (int i = 0; i < maxNumEcBytes; ++i) {
      for (int j = 0; j < blocks.length; ++j) {
        ByteArray ecBytes = blocks[j].getErrorCorrectionBytes();
        if (i < ecBytes.size()) {
          result.appendBits(ecBytes.at(i), 8);
        }
      }
    }
    // Should be same.
    if (numTotalBytes != result.sizeInBytes()) {
      throw Exception(
          "Interleaving error: $numTotalBytes and ${result.sizeInBytes()} differ.");
    }
  }

  static ByteArray _generateECBytes(
      ByteArray dataBytes, int numEcBytesInBlock) {
    int numDataBytes = dataBytes.size();
    List<int> toEncode = List<int>.filled(numDataBytes + numEcBytesInBlock, 0);
    for (int i = 0; i < numDataBytes; i++) {
      toEncode[i] = dataBytes.at(i);
    }
    ReedSolomonEncoder(GF256.QR_CODE_FIELD).encode(toEncode, numEcBytesInBlock);
    ByteArray ecBytes = ByteArray(numEcBytesInBlock);
    for (int i = 0; i < numEcBytesInBlock; i++) {
      ecBytes.set(i, toEncode[numDataBytes + i]);
    }
    return ecBytes;
  }

  static void _appendModeInfo(Mode mode, BitVector bits) {
    bits.appendBits(mode.getBits(), 4);
  }

  static void _appendLengthInfo(
      int numLetters, int version, Mode mode, BitVector bits) {
    int numBits =
        mode.getCharacterCountBits(Version.getVersionForNumber(version));
    if (numLetters > ((1 << numBits) - 1)) {
      throw Exception(
          "$numLetters is bigger than ${((1 << numBits) - 1)}"); // WriterException
    }
    bits.appendBits(numLetters, numBits);
  }

  static void appendBytes(
      String content, Mode mode, BitVector bits, String encoding) {
    if (mode == Mode.NUMERIC) {
      _appendNumericBytes(content, bits);
    } else {
      if (mode == Mode.ALPHANUMERIC) {
        _appendAlphanumericBytes(content, bits);
      } else {
        if (mode == Mode.BYTE) {
          _append8BitBytes(content, bits, encoding);
        } else {
          if (mode == Mode.KANJI) {
            _appendKanjiBytes(content, bits);
          } else {
            throw Exception("Invalid mode: $mode"); // WriterException
          }
        }
      }
    }
  }

  static void _appendNumericBytes(String content, BitVector bits) {
    int length = content.length;
    int i = 0;
    while (i < length) {
      int num1 = content.codeUnitAt(i) - 48; // '0'
      if (i + 2 < length) {
        // Encode three numeric letters in ten bits.
        int num2 = content.codeUnitAt(i + 1) - 48;
        int num3 = content.codeUnitAt(i + 2) - 48;
        bits.appendBits(num1 * 100 + num2 * 10 + num3, 10);
        i += 3;
      } else {
        if (i + 1 < length) {
          // Encode two numeric letters in seven bits.
          int num2 = content.codeUnitAt(i + 1) - 48;
          bits.appendBits(num1 * 10 + num2, 7);
          i += 2;
        } else {
          // Encode one numeric letter in four bits.
          bits.appendBits(num1, 4);
          i++;
        }
      }
    }
  }

  static void _appendAlphanumericBytes(String content, BitVector bits) {
    int length = content.length;
    int i = 0;
    while (i < length) {
      int code1 = getAlphanumericCode(content.codeUnitAt(i));
      if (code1 == -1) {
        throw Exception(); // WriterException
      }
      if (i + 1 < length) {
        int code2 = getAlphanumericCode(content.codeUnitAt(i + 1));
        if (code2 == -1) {
          throw Exception(); // WriterException
        }
        // Encode two alphanumeric letters in 11 bits.
        bits.appendBits(code1 * 45 + code2, 11);
        i += 2;
      } else {
        // Encode one alphanumeric letter in six bits.
        bits.appendBits(code1, 6);
        i++;
      }
    }
  }

  static void _append8BitBytes(
      String content, BitVector bits, String encoding) {
    List<int> bytes;
    try {
      if (encoding == "ISO-8859-1") {
        bytes = latin1.encode(content);
      } else if (encoding == "UTF-8") {
        bytes = utf8.encode(content);
      } else {
        // Fallback or throw?
        // C# catches ArgumentException.
        // We'll default to latin1 or throw.
        // C# code uses encoding.
        // Since I cannot dynamically load encoding, I will throw if not one of these.
        throw ArgumentError("Unsupported encoding: $encoding");
      }
    } catch (e) {
      throw Exception(e.toString()); // WriterException
    }
    for (int i = 0; i < bytes.length; ++i) {
      bits.appendBits(bytes[i], 8);
    }
  }

  static void _appendKanjiBytes(String content, BitVector bits) {
    // Kanji not supported without 3rd party lib
    throw UnsupportedError("Kanji mode not supported in this port");
  }

  static void _appendECI(CharacterSetECI eci, BitVector bits) {
    bits.appendBits(Mode.ECI.getBits(), 4);
    // This is correct for values up to 127, which is all we need now.
    bits.appendBits(eci.getValue(), 8);
  }
}
