part of 'jpeg_decoder.dart';

/// Scan-level driving of the arithmetic entropy decoder for the DCT-based
/// processes: SOF9 (extended sequential) and SOF10 (progressive), T.81 F.2.4
/// and G.2.
///
/// The models themselves live in [JpegArithmeticEntropy]; what is here is the
/// MCU walk, the restart handling and the hand-off to the IDCT, which mirror
/// the Huffman paths in `jpeg_decoder.dart`.
extension _ArithmeticScans on _Decoder {
  /// Reads one arithmetic-coded scan. [ss]/[se] are the spectral band and
  /// [ah]/[al] the successive-approximation positions; a sequential scan
  /// carries 0/63/0/0 there and the values are inert.
  void _readArithmeticScan(
      List<_Component> scan, int ss, int se, int ah, int al) {
    if (ss > se || se > 63) {
      throw const JpegDecodeException(
          'A scan declares a spectral band outside 0..63.');
    }
    if (progressive && ss != 0 && scan.length != 1) {
      throw const JpegDecodeException(
          'An AC progressive scan must carry exactly one component.');
    }

    final entropy = JpegArithmeticEntropy(arithConditioning);

    // T.81 F.2.4: at the start of a scan the statistics areas the scan uses are
    // reset to the standard initial state, as part of Initdec.
    void resetStatistics() {
      for (final component in scan) {
        if (!progressive || (ss == 0 && ah == 0)) {
          entropy.resetDcStats(component.dcTable);
        }
        if (!progressive || ss != 0) {
          entropy.resetAcStats(component.acTable);
        }
      }
      if (!progressive || (ss == 0 && ah == 0)) entropy.resetPredictions();
    }

    // T.81 A.2.2/A.2.3: an interleaved scan walks MCUs, a single-component
    // scan walks that component's own block grid.
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

    entropy.start(data, offset);
    var mcu = 0;
    while (mcu < total) {
      resetStatistics();
      final stop = mcu + interval < total ? mcu + interval : total;
      for (; mcu < stop; mcu++) {
        if (interleaved) {
          final row = mcu ~/ mcusPerLine;
          final column = mcu % mcusPerLine;
          for (var ci = 0; ci < scan.length; ci++) {
            final component = scan[ci];
            for (var v = 0; v < component.v; v++) {
              for (var h = 0; h < component.h; h++) {
                _decodeArithmeticBlock(
                    entropy,
                    ci,
                    component,
                    row * component.v + v,
                    column * component.h + h,
                    ss,
                    se,
                    ah,
                    al);
              }
            }
          }
        } else {
          final component = scan.first;
          _decodeArithmeticBlock(
              entropy,
              0,
              component,
              mcu ~/ component.blocksPerLineForScan,
              mcu % component.blocksPerLineForScan,
              ss,
              se,
              ah,
              al);
        }
        if (entropy.corrupt) break;
      }
      if (entropy.corrupt) break;
      if (mcu < total) {
        // A restart marker ends the entropy-coded segment: the decoder is
        // re-initialised on the far side of it, per T.81 F.2.4.4.
        offset = entropy.position;
        if (!_skipRestart()) break;
        entropy.start(data, offset);
      }
    }

    offset = entropy.position;
    _alignToMarker();
  }

  void _decodeArithmeticBlock(
    JpegArithmeticEntropy entropy,
    int ci,
    _Component component,
    int blockRow,
    int blockColumn,
    int ss,
    int se,
    int ah,
    int al,
  ) {
    final coefficients = component.coefficients;
    if (coefficients == null) {
      // Sequential: straight from block to plane, no coefficient store.
      final quant = quantTables[component.quantTable];
      if (quant == null) {
        throw const JpegDecodeException(
            'The scan uses a quantisation table the file never defined.');
      }
      _coefficients.fillRange(0, 64, 0);
      _coefficients[0] = entropy.decodeDcDifference(ci, component.dcTable);
      entropy.decodeAcCoefficients(
          component.acTable, _coefficients, 0, 1, 63, 0, _zigZag);
      _idct(quant, component, blockRow, blockColumn);
      return;
    }

    final base = (blockRow * component.blocksPerLine + blockColumn) * 64;
    if (base < 0 || base + 64 > coefficients.length) return;

    if (ss == 0) {
      if (se != 0) {
        throw const JpegDecodeException(
            'A progressive DC scan must have Se = 0.');
      }
      if (ah == 0) {
        coefficients[base] =
            entropy.decodeDcDifference(ci, component.dcTable) << al;
      } else if (entropy.decodeCorrectionBit() != 0) {
        coefficients[base] |= 1 << al;
      }
      return;
    }

    if (ah == 0) {
      entropy.decodeAcCoefficients(
          component.acTable, coefficients, base, ss, se, al, _zigZag);
    } else {
      entropy.refineAcCoefficients(
          component.acTable, coefficients, base, ss, se, al, _zigZag);
    }
  }
}
