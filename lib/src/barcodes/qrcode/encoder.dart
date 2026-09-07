import 'dart:convert';

import 'bit_vector.dart';
import 'byte_matrix.dart';
import 'encode_hint_type.dart';
import 'error_correction_level.dart';
import 'gf_256.dart';
import 'mask_util.dart';
import 'matrix_util.dart';
import 'mode.dart';
import 'qr_code.dart';
import 'reed_solomon_encoder.dart';
import 'version.dart';

/// Builds a single-segment QR symbol from text and a correction level.
class CraftEncoder {
  static const _alphabet = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

  static int getAlphanumericCode(int code) => code < 0 || code > 127
      ? -1
      : _alphabet.indexOf(String.fromCharCode(code));

  static CraftMode chooseMode(String content, [String? encoding]) {
    if (content.isEmpty || encoding == 'Shift_JIS') return CraftMode.BYTE;
    if (content.codeUnits.every((unit) => unit >= 48 && unit <= 57)) {
      return CraftMode.NUMERIC;
    }
    return content.codeUnits.every((unit) => getAlphanumericCode(unit) >= 0)
        ? CraftMode.ALPHANUMERIC
        : CraftMode.BYTE;
  }

  static void appendBytes(
      String content, CraftMode mode, CraftBitVector bits, String encoding) {
    if (mode == CraftMode.KANJI) {
      throw UnsupportedError('QR Kanji requires a Shift-JIS text codec');
    }
    if (mode == CraftMode.BYTE) {
      final converter = switch (encoding) {
        'ISO-8859-1' => latin1,
        'UTF-8' => utf8,
        _ => throw ArgumentError.value(encoding, 'encoding',
            'QR byte segments support ISO-8859-1 and UTF-8'),
      };
      final bytes = converter.encode(content);
      for (final byte in bytes) {
        bits.appendBits(byte, 8);
      }
      return;
    }
    final numeric = mode == CraftMode.NUMERIC;
    if (!numeric && mode != CraftMode.ALPHANUMERIC) {
      throw ArgumentError.value(mode, 'mode', 'Not a QR text segment mode');
    }
    final values = content.codeUnits.map((unit) {
      final value = numeric ? unit - 48 : getAlphanumericCode(unit);
      if (value < 0 || value >= (numeric ? 10 : 45)) {
        throw FormatException(
            'Character does not belong to the selected QR alphabet');
      }
      return value;
    }).toList();
    final groupSize = numeric ? 3 : 2;
    for (var offset = 0; offset < values.length; offset += groupSize) {
      final remaining = values.length - offset;
      final count = remaining < groupSize ? remaining : groupSize;
      var combined = 0;
      for (var index = 0; index < count; index++) {
        combined = combined * (numeric ? 10 : 45) + values[offset + index];
      }
      final width = numeric ? [0, 4, 7, 10][count] : [0, 6, 11][count];
      bits.appendBits(combined, width);
    }
  }

  static void encode(String content, CraftErrorCorrectionLevel ecLevel,
      Map<CraftEncodeHintType, dynamic>? hints, CraftQRCode qrCode) {
    final encoding =
        hints?[CraftEncodeHintType.CHARACTER_SET] as String? ?? 'ISO-8859-1';
    final minimum =
        (hints?[CraftEncodeHintType.MIN_VERSION_NR] as int? ?? 1).clamp(1, 40);
    final mode = chooseMode(content, encoding);
    final payload = CraftBitVector();
    appendBytes(content, mode, payload, encoding);
    final count =
        mode == CraftMode.BYTE ? payload.sizeInBytes() : content.length;
    final prefix = CraftBitVector();
    if (mode == CraftMode.BYTE && encoding != 'ISO-8859-1') {
      // The supported nondefault codec is UTF-8, ECI assignment 26.
      _writeAssignment(prefix, 26);
    }
    prefix.appendBits(mode.getBits(), 4);

    CraftVersion? selected;
    var capacity = 0;
    for (var candidate = minimum; candidate <= 40; candidate++) {
      final version = CraftVersion.getVersionForNumber(candidate);
      final width = mode.getCharacterCountBits(version);
      final available = version.getTotalCodewords() -
          version.getECBlocksForLevel(ecLevel).getTotalECCodewords();
      if (count < (1 << width) &&
          prefix.size() + width + payload.size() <= available * 8) {
        selected = version;
        capacity = available;
        break;
      }
    }
    if (selected == null) {
      throw ArgumentError(
          'Text exceeds QR version 40 capacity at this correction level');
    }
    prefix.appendBits(count, mode.getCharacterCountBits(selected));
    prefix.appendBitVector(payload);
    _fillCapacity(prefix, capacity);
    final blocks = selected.getECBlocksForLevel(ecLevel).getNumBlocks();
    final stream =
        _codewords(prefix, selected.getTotalCodewords(), capacity, blocks);
    final versionNumber = selected.getVersionNumber();
    final side = selected.getDimensionForVersion();
    CraftByteMatrix? chosen;
    int? score;
    var mask = 0;
    for (var trial = 0; trial < 8; trial++) {
      final matrix = CraftByteMatrix(side, side);
      CraftMatrixUtil.buildMatrix(
          stream, ecLevel, versionNumber, trial, matrix);
      final penalty = CraftMaskUtil.repeatedRunPenalty(matrix) +
          CraftMaskUtil.uniformSquarePenalty(matrix) +
          CraftMaskUtil.finderPatternPenalty(matrix) +
          CraftMaskUtil.darkBalancePenalty(matrix);
      if (score == null || penalty < score) {
        score = penalty;
        chosen = matrix;
        mask = trial;
      }
    }
    qrCode.setMode(mode);
    qrCode.setECLevel(ecLevel);
    qrCode.setVersion(versionNumber);
    qrCode.setNumTotalBytes(selected.getTotalCodewords());
    qrCode.setNumDataBytes(capacity);
    qrCode.setNumECBytes(selected.getTotalCodewords() - capacity);
    qrCode.setNumRSBlocks(blocks);
    qrCode.setMatrixWidth(side);
    qrCode.setMaskPattern(mask);
    qrCode.setMatrix(chosen!);
  }

  static void _writeAssignment(CraftBitVector bits, int value) {
    RangeError.checkValueInInterval(value, 0, 999999, 'ECI assignment');
    bits.appendBits(CraftMode.ECI.getBits(), 4);
    if (value < 128) {
      bits.appendBits(value, 8);
    } else if (value < 16384) {
      bits.appendBits(0x8000 | value, 16);
    } else {
      bits.appendBits(0xc00000 | value, 24);
    }
  }

  static void _fillCapacity(CraftBitVector bits, int bytes) {
    final budget = bytes * 8;
    final remaining = budget - bits.size();
    bits.appendBits(0, remaining < 4 ? remaining : 4);
    if (bits.size() % 8 != 0) bits.appendBits(0, 8 - bits.size() % 8);
    var padding = 0;
    while (bits.size() < budget) {
      bits.appendBits(padding.isEven ? 236 : 17, 8);
      padding++;
    }
  }

  static CraftBitVector _codewords(
      CraftBitVector data, int total, int dataCount, int blockCount) {
    final parityCount = (total - dataCount) ~/ blockCount;
    final shortLength = dataCount ~/ blockCount;
    final shortBlocks = blockCount - dataCount % blockCount;
    final source = data.getArray();
    final dataBlocks = <List<int>>[];
    final parityBlocks = <List<int>>[];
    final parityEncoder = CraftReedSolomonEncoder(CraftGF256.QR_CODE_FIELD);
    var offset = 0;
    for (var index = 0; index < blockCount; index++) {
      final length = shortLength + (index >= shortBlocks ? 1 : 0);
      final word = [
        ...source.sublist(offset, offset + length),
        ...List<int>.filled(parityCount, 0)
      ];
      parityEncoder.encode(word, parityCount);
      dataBlocks.add(word.sublist(0, length));
      parityBlocks.add(word.sublist(length));
      offset += length;
    }
    final result = CraftBitVector();
    for (final group in [dataBlocks, parityBlocks]) {
      var column = 0;
      while (group.any((block) => column < block.length)) {
        for (final block in group) {
          if (column < block.length) result.appendBits(block[column], 8);
        }
        column++;
      }
    }
    return result;
  }
}
