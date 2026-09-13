part of 'jpeg_decoder.dart';

/// One frame of a hierarchical sequence, lifted out of the stream as a
/// standalone single-frame JPEG.
class _HierarchicalFrame {
  /// The SOFn marker code the frame opened with.
  final int marker;

  /// Whether the EXP segment before this frame asked for the reference
  /// components to be doubled, T.81 B.3.3.
  final bool expandHorizontally;
  final bool expandVertically;

  /// SOI, every table and miscellaneous segment in force, the frame, EOI.
  final Uint8List stream;

  const _HierarchicalFrame(
      this.marker, this.expandHorizontally, this.expandVertically, this.stream);

  bool get isDifferential =>
      marker == 0xC5 ||
      marker == 0xC6 ||
      marker == 0xC7 ||
      marker == 0xCD ||
      marker == 0xCE ||
      marker == 0xCF;
}

/// A component plane at one frame's resolution.
class _ReferencePlane {
  final int width;
  final int height;
  final Int32List samples;

  _ReferencePlane(this.width, this.height)
      : samples = Int32List(width * height);

  _ReferencePlane.of(this.width, this.height, this.samples);
}

/// The hierarchical mode of operation, ITU-T T.81 Annex J.
///
/// A hierarchical image is a non-differential frame followed by differential
/// frames that each add detail. Between frames a reference component may be
/// doubled in either direction by the bi-linear filter of J.1.1.2, and a
/// differential frame's output is added to it modulo 2^16 (J.2.1).
///
/// Only the lossless processes are read here: a non-differential SOF3 or SOF11
/// followed by differential SOF7 or SOF15 frames. The differential DCT
/// processes would need the IDCT to produce signed output, which the
/// sequential path is not built for, and are refused rather than guessed at.
extension _HierarchicalDecoding on _Decoder {
  JpegImage _decodeHierarchical() {
    final frames = _splitHierarchicalFrames();
    if (frames.isEmpty) {
      throw const JpegDecodeException(
          'A hierarchical JPEG carries no frames after its DHP segment.');
    }

    List<_ReferencePlane>? references;
    _Decoder? last;

    for (final frame in frames) {
      final sub = _Decoder(frame.stream);
      sub._readFrameHeader(stopAtScan: false);
      if (sub.refusal != null) throw JpegDecodeException(sub.refusal!);
      if (!sub.lossless) {
        throw const JpegDecodeException(
            'Hierarchical JPEG is supported only for the lossless processes '
            'of Annex H.');
      }
      if (sub.components.length != components.length) {
        throw const JpegDecodeException(
            'A hierarchical frame declares a different number of components '
            'than the DHP segment.');
      }

      final decoded = [
        for (final component in sub.components)
          _ReferencePlane.of(
            component.planeStride,
            component.samples!.length ~/ component.planeStride,
            component.samples!,
          ),
      ];
      // J.2.3.2: a non-zero point transform scales the differential output.
      final shift = sub.scanPointTransform;

      if (!frame.isDifferential) {
        references = decoded;
      } else {
        if (references == null) {
          throw const JpegDecodeException(
              'A hierarchical JPEG opens with a differential frame.');
        }
        if (frame.expandHorizontally || frame.expandVertically) {
          references = [
            for (final plane in references)
              _expandReference(
                  plane, frame.expandHorizontally, frame.expandVertically),
          ];
        }
        for (var ci = 0; ci < decoded.length; ci++) {
          references[ci] = _addDifferential(references[ci], decoded[ci], shift);
        }
      }
      last = sub;
    }

    final result = last!;
    final planes = references!;
    for (var ci = 0; ci < result.components.length; ci++) {
      final component = result.components[ci];
      final plane = planes[ci];
      final samples = component.samples!;
      final stride = component.planeStride;
      final lines = samples.length ~/ stride;
      for (var y = 0; y < lines; y++) {
        final sourceRow =
            (y < plane.height ? y : plane.height - 1) * plane.width;
        for (var x = 0; x < stride; x++) {
          samples[y * stride + x] = plane
              .samples[sourceRow + (x < plane.width ? x : plane.width - 1)];
        }
      }
      result._writeLosslessPlane(component, 0);
    }
    return result._assemble();
  }

  /// Adds a differential frame to its reference, modulo 2^16, J.2.1.
  ///
  /// The reference may be larger than the differential frame when the
  /// expansion rounded up, so the result keeps the frame's own size.
  _ReferencePlane _addDifferential(_ReferencePlane reference,
      _ReferencePlane difference, int pointTransform) {
    final out = _ReferencePlane(difference.width, difference.height);
    for (var y = 0; y < difference.height; y++) {
      final referenceRow =
          (y < reference.height ? y : reference.height - 1) * reference.width;
      for (var x = 0; x < difference.width; x++) {
        final base = reference.samples[
            referenceRow + (x < reference.width ? x : reference.width - 1)];
        final delta = difference.samples[y * difference.width + x];
        out.samples[y * difference.width + x] =
            (base + (delta << pointTransform)) & 0xFFFF;
      }
    }
    return out;
  }

  /// The upsampling filter of T.81 J.1.1.2: bi-linear interpolation that
  /// doubles the resolution, horizontally first and then vertically.
  ///
  /// The left-most column and the top line of the result match the source; the
  /// right column and bottom line are replicated to feed the last
  /// interpolation, and the division truncates.
  _ReferencePlane _expandReference(
      _ReferencePlane source, bool horizontally, bool vertically) {
    var plane = source;
    if (horizontally) {
      final out = _ReferencePlane(plane.width * 2, plane.height);
      for (var y = 0; y < plane.height; y++) {
        final from = y * plane.width;
        final to = y * out.width;
        for (var x = 0; x < plane.width; x++) {
          final a = plane.samples[from + x];
          final b = plane.samples[from + (x + 1 < plane.width ? x + 1 : x)];
          out.samples[to + 2 * x] = a;
          out.samples[to + 2 * x + 1] = (a + b) ~/ 2;
        }
      }
      plane = out;
    }
    if (vertically) {
      final out = _ReferencePlane(plane.width, plane.height * 2);
      for (var y = 0; y < plane.height; y++) {
        final above = y * plane.width;
        final below = (y + 1 < plane.height ? y + 1 : y) * plane.width;
        final to = 2 * y * out.width;
        for (var x = 0; x < plane.width; x++) {
          final a = plane.samples[above + x];
          final b = plane.samples[below + x];
          out.samples[to + x] = a;
          out.samples[to + out.width + x] = (a + b) ~/ 2;
        }
      }
      plane = out;
    }
    return plane;
  }

  /// Splits the stream into standalone single-frame JPEGs.
  ///
  /// Table and miscellaneous segments accumulate: one defined before frame *k*
  /// is in force for every later frame, so each synthesised stream carries the
  /// ones that precede it, in order.
  List<_HierarchicalFrame> _splitHierarchicalFrames() {
    final tables = <int>[];
    final frames = <_HierarchicalFrame>[];
    var expandHorizontally = false;
    var expandVertically = false;

    var at = 2; // Past the SOI.
    while (at + 1 < data.length) {
      if (data[at] != 0xFF) {
        at++;
        continue;
      }
      var markerAt = at;
      while (markerAt + 1 < data.length && data[markerAt + 1] == 0xFF) {
        markerAt++;
      }
      final code = data[markerAt + 1];
      final payloadAt = markerAt + 2;
      if (code == 0xD9) break; // EOI.
      if (code == 0xD8 || code == 0x01 || (code >= 0xD0 && code <= 0xD7)) {
        at = payloadAt;
        continue;
      }
      if (payloadAt + 1 >= data.length) break;
      final length = (data[payloadAt] << 8) | data[payloadAt + 1];
      if (length < 2) {
        throw const JpegDecodeException('A marker segment declares a '
            'length shorter than its own length field.');
      }
      final segmentEnd = payloadAt + length;

      if (_isFrameMarker(code)) {
        final end = _endOfFrame(segmentEnd);
        final stream = <int>[0xFF, 0xD8, ...tables];
        stream.addAll(data.sublist(markerAt, end));
        stream.addAll([0xFF, 0xD9]);
        frames.add(_HierarchicalFrame(code, expandHorizontally,
            expandVertically, Uint8List.fromList(stream)));
        expandHorizontally = false;
        expandVertically = false;
        at = end;
        continue;
      }

      switch (code) {
        case 0xDE: // DHP: already read, and it is not a frame.
          break;
        case 0xDF: // EXP.
          if (length != 3) {
            throw const JpegDecodeException(
                'An EXP segment must be three bytes long.');
          }
          final expand = data[payloadAt + 2];
          expandHorizontally = (expand >> 4) == 1;
          expandVertically = (expand & 0x0F) == 1;
          if ((expand >> 4) > 1 || (expand & 0x0F) > 1) {
            throw const JpegDecodeException(
                'An EXP segment may only ask for a factor of two.');
          }
        default:
          // DQT, DHT, DAC, DRI, APPn, COM: in force for every later frame.
          tables.addAll(data.sublist(markerAt, segmentEnd));
      }
      at = segmentEnd;
    }
    return frames;
  }

  static bool _isFrameMarker(int code) =>
      (code >= 0xC0 && code <= 0xCF) &&
      code != 0xC4 && // DHT
      code != 0xC8 && // JPG, reserved
      code != 0xCC; // DAC

  /// The SOFn code of the first frame after the current position, or -1.
  int _firstFrameMarker() {
    for (var at = offset; at + 1 < data.length; at++) {
      if (data[at] != 0xFF) continue;
      final code = data[at + 1];
      if (_isFrameMarker(code)) return code;
    }
    return -1;
  }

  /// Walks past a frame's scans to the marker that ends it.
  ///
  /// Table and miscellaneous segments are ambiguous: between two scans they
  /// belong to this frame, after the last one they belong to the next. A run
  /// of them is therefore held back until the marker that follows says which,
  /// and only a scan claims it.
  int _endOfFrame(int from) {
    var at = from;
    var pending = -1;
    while (at + 1 < data.length) {
      if (data[at] != 0xFF) {
        at++;
        continue;
      }
      final code = data[at + 1];
      if (code == 0xFF) {
        at++;
        continue;
      }
      if (code == 0x00 || (code >= 0xD0 && code <= 0xD7)) {
        at += 2; // Stuffing or a restart: still entropy-coded data.
        continue;
      }
      if (code == 0xD9 ||
          code == 0xDE ||
          code == 0xDF ||
          _isFrameMarker(code)) {
        return pending >= 0 ? pending : at;
      }
      if (at + 3 >= data.length) {
        return pending >= 0 ? pending : data.length;
      }
      final length = (data[at + 2] << 8) | data[at + 3];
      if (length < 2) return pending >= 0 ? pending : at;
      if (code == 0xDA) {
        // A scan: it claims the tables that preceded it, and its entropy-coded
        // data is stepped over by the loop above.
        pending = -1;
      } else if (pending < 0) {
        pending = at;
      }
      at += 2 + length;
    }
    return pending >= 0 ? pending : data.length;
  }
}
