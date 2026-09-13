part of 'jpeg_decoder.dart';

/// The lossless mode of operation, ITU-T T.81 Annex H: SOF3 with Huffman
/// coding and SOF11 with arithmetic coding, at 2 to 16 bits per sample.
///
/// Nothing here is DCT: the data unit is one sample, the sample is predicted
/// from its already-decoded neighbours by one of the seven predictors of
/// Table H.1, and what the entropy coder carries is the prediction error taken
/// modulo 2^16.
extension _LosslessScans on _Decoder {
  /// Sizes the per-component sample grids for a lossless frame.
  ///
  /// A component holds `ceil(X * Hi / Hmax)` samples per line and
  /// `ceil(Y * Vi / Vmax)` lines, T.81 A.1.1, rounded up to whole MCUs when
  /// the scan interleaves it, A.2.4.
  void _prepareLosslessComponents() {
    for (final component in components) {
      final width = (frameWidth * component.h + maxH - 1) ~/ maxH;
      final height = (frameHeight * component.v + maxV - 1) ~/ maxV;
      component.blocksPerLineForScan = width;
      component.blocksPerColumnForScan = height;

      final paddedWidth = mcusPerLine * component.h;
      final paddedHeight = mcusPerColumn * component.v;
      component.blocksPerLine = paddedWidth;
      component.blocksPerColumn = paddedHeight;

      component.planeStride = paddedWidth > width ? paddedWidth : width;
      final lines = paddedHeight > height ? paddedHeight : height;
      component.samples = Int32List(component.planeStride * lines);
      component.plane = Uint8List(component.planeStride * lines);
      component.prediction = 0;
    }
  }

  /// Reads one lossless scan.
  ///
  /// [predictor] is the scan header's Ss, the selection value of Table H.1;
  /// [pointTransform] is Al, the Pt of A.4.
  void _readLosslessScan(
      List<_Component> scan, int predictor, int pointTransform) {
    if (predictor < 0 || predictor > 7) {
      throw JpegDecodeException('A lossless scan selects predictor $predictor, '
          'which Table H.1 does not define.');
    }
    if (predictor == 0 && !differential) {
      throw const JpegDecodeException(
          'Predictor 0 is only defined for the differential frames of the '
          'hierarchical mode.');
    }
    final effective = samplePrecision - pointTransform;
    if (effective < 1 || effective > 16) {
      throw JpegDecodeException('A point transform of $pointTransform leaves '
          '$effective bits of a $samplePrecision-bit sample.');
    }
    // T.81 H.1.2.1: the prediction at the start of the first line, and of the
    // first line of every restart interval, is 2^(P - Pt - 1).
    final initial = 1 << (effective - 1);
    scanPointTransform = pointTransform;

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

    // Conditioning categories of the differences already decoded, one array
    // per component in the scan, for the two-dimensional model of H.1.2.3.1.
    final categories = [
      for (final component in scan)
        arithmetic ? Uint8List(component.samples!.length) : Uint8List(0),
    ];
    final restartRow = List<int>.filled(scan.length, 0);

    JpegArithmeticEntropy? entropy;
    if (arithmetic) {
      entropy = JpegArithmeticEntropy(arithConditioning);
      entropy.start(data, offset);
    } else {
      bitBuffer = 0;
      bitCount = 0;
      hitMarker = false;
    }

    /// Decodes the prediction error for one sample of component [ci].
    int difference(int ci, _Component component, int index, Uint8List category,
        int stride, bool firstRow, bool firstColumn) {
      if (entropy != null) {
        // Table H.3: the left category is zero at the start of a line and the
        // one above is zero on the first line of the interval.
        final left = firstColumn ? 0 : category[index - 1];
        final above = firstRow ? 0 : category[index - stride];
        final value =
            entropy.decodeLosslessDifference(component.dcTable, left, above);
        category[index] = entropy.lastLosslessCategory;
        return value;
      }
      final table = dcTables[component.dcTable];
      if (table == null) {
        throw const JpegDecodeException(
            'The scan uses a Huffman table the file never defined.');
      }
      final size = _decodeSymbol(table);
      // Table H.2 extends the DC code table by one entry: SSSS = 16 codes a
      // difference of 32 768 with no appended bits.
      if (size == 16) return 32768;
      if (size > 16) {
        throw const JpegDecodeException(
            'A lossless difference declares a category above 16.');
      }
      return size == 0 ? 0 : _Decoder._extend(_bits(size), size);
    }

    void decodeSample(int ci, _Component component, int row, int column) {
      final samples = component.samples!;
      final stride = component.planeStride;
      final index = row * stride + column;
      if (index < 0 || index >= samples.length) return;

      final firstRow = row == restartRow[ci];
      final firstColumn = column == 0;
      final int px;
      if (predictor == 0) {
        // Annex J: a differential frame codes the difference directly.
        px = 0;
      } else if (firstRow) {
        px = firstColumn ? initial : samples[index - 1];
      } else if (firstColumn) {
        px = samples[index - stride];
      } else {
        final ra = samples[index - 1];
        final rb = samples[index - stride];
        final rc = samples[index - stride - 1];
        px = switch (predictor) {
          1 => ra,
          2 => rb,
          3 => rc,
          4 => ra + rb - rc,
          5 => ra + ((rb - rc) >> 1),
          6 => rb + ((ra - rc) >> 1),
          _ => (ra + rb) >> 1,
        };
      }

      final diff = difference(
          ci, component, index, categories[ci], stride, firstRow, firstColumn);
      // H.1.2.1: the difference is added modulo 2^16.
      samples[index] = (px + diff) & 0xFFFF;
    }

    var mcu = 0;
    while (mcu < total) {
      if (entropy != null) {
        for (final component in scan) {
          entropy.resetDcStats(component.dcTable);
        }
        for (final array in categories) {
          array.fillRange(0, array.length, 0);
        }
      }
      for (var ci = 0; ci < scan.length; ci++) {
        restartRow[ci] = interleaved
            ? (mcu ~/ mcusPerLine) * scan[ci].v
            : mcu ~/ scan[ci].blocksPerLineForScan;
      }

      final stop = mcu + interval < total ? mcu + interval : total;
      for (; mcu < stop; mcu++) {
        if (interleaved) {
          final row = mcu ~/ mcusPerLine;
          final column = mcu % mcusPerLine;
          for (var ci = 0; ci < scan.length; ci++) {
            final component = scan[ci];
            for (var v = 0; v < component.v; v++) {
              for (var h = 0; h < component.h; h++) {
                decodeSample(ci, component, row * component.v + v,
                    column * component.h + h);
              }
            }
          }
        } else {
          final component = scan.first;
          decodeSample(0, component, mcu ~/ component.blocksPerLineForScan,
              mcu % component.blocksPerLineForScan);
        }
        if (entropy != null && entropy.corrupt) break;
      }
      if (entropy != null && entropy.corrupt) break;
      if (mcu < total) {
        if (entropy != null) offset = entropy.position;
        if (!_skipRestart()) break;
        if (entropy != null) entropy.start(data, offset);
      }
    }

    if (entropy != null) offset = entropy.position;
    _alignToMarker();

    for (final component in scan) {
      _writeLosslessPlane(component, pointTransform);
    }
  }

  /// Turns the decoded samples into the eight-bit plane [JpegImage] carries.
  ///
  /// H.2.2 makes the decoder multiply its output by 2^Pt; anything wider than
  /// eight bits is then scaled down, since [JpegImage] is a byte image.
  void _writeLosslessPlane(_Component component, int pointTransform) {
    final samples = component.samples;
    if (samples == null) return;
    final plane = component.plane;
    final shift = samplePrecision - 8;
    for (var i = 0; i < samples.length; i++) {
      var value = samples[i] << pointTransform;
      value = shift > 0 ? value >> shift : value << -shift;
      plane[i] = value < 0
          ? 0
          : value > 255
              ? 255
              : value;
    }
  }
}
