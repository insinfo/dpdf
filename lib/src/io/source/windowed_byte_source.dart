import 'dart:typed_data';

import 'pdf_byte_source.dart';

/// Greatest byte position at which a PDF header may begin.
///
/// ISO 32000-2, 7.5.2 allows arbitrary bytes before `%PDF-`, and a conforming
/// reader is expected to look only at the beginning of the file. Every known
/// implementation caps that search at one kibibyte, so a `%` at index 1023 is
/// the last one accepted here.
const int pdfHeaderSearchLimit = 1024;

/// `%PDF-` in Latin-1.
const List<int> _pdfMarker = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];

/// `%FDF-` in Latin-1.
const List<int> _fdfMarker = <int>[0x25, 0x46, 0x44, 0x46, 0x2D];

/// A [PdfByteSource] that exposes a suffix of another source as if it were a
/// whole file.
///
/// Position zero of the window is byte [start] of the delegate, and
/// [length] is shortened accordingly. This is how a PDF whose header does not
/// sit at byte zero is read: ISO 32000-2, 7.5.2 states that byte offsets are
/// counted from the PERCENT SIGN of `%PDF-`, so presenting the source already
/// shifted keeps every offset in the cross-reference table meaningful without
/// the rest of the reader having to know that a prefix exists.
class WindowedByteSource implements PdfByteSource {
  final PdfByteSource _source;

  /// Offset in the delegate that the window presents as position zero.
  final int start;

  final bool _ownsSource;

  /// Wraps [source] so that its byte [start] becomes position zero.
  ///
  /// When [ownsSource] is false, [close] leaves the delegate open.
  WindowedByteSource(this._source, this.start, {bool ownsSource = true})
      : _ownsSource = ownsSource {
    RangeError.checkNotNegative(start, 'start');
  }

  /// Whether the bytes are already materialized behind the window.
  bool get isMemoryBacked => _source is PdfMemorySource;

  @override
  int get length {
    final remaining = _source.length - start;
    return remaining > 0 ? remaining : 0;
  }

  @override
  int byteAt(int offset) {
    RangeError.checkNotNegative(offset, 'offset');
    if (offset >= length) return -1;
    return _source.byteAt(start + offset);
  }

  @override
  int readInto(int position, Uint8List target, int offset, int count) {
    RangeError.checkNotNegative(position, 'position');
    RangeError.checkValidRange(offset, offset + count, target.length);
    if (count == 0) return 0;
    final available = length - position;
    if (available <= 0) return -1;
    final size = count < available ? count : available;
    return _source.readInto(start + position, target, offset, size);
  }

  @override
  void close() {
    if (_ownsSource) _source.close();
  }
}

int _indexOfMarker(Uint8List prefix, List<int> marker, int limit) {
  final last = prefix.length - marker.length;
  final bound = last < limit ? last : limit;
  for (var index = 0; index <= bound; index++) {
    if (prefix[index] != marker[0]) continue;
    var matched = 1;
    while (
        matched < marker.length && prefix[index + matched] == marker[matched]) {
      matched++;
    }
    if (matched == marker.length) return index;
  }
  return -1;
}

/// Position of the `%PDF-` (or `%FDF-`) header inside [source], or -1.
///
/// Only headers that begin at or before byte [limit] - 1 are reported; a marker
/// further in is treated as ordinary file content, not as a header.
int findPdfHeaderOffset(PdfByteSource source,
    {int limit = pdfHeaderSearchLimit}) {
  RangeError.checkNotNegative(limit, 'limit');
  // The last acceptable marker starts at limit - 1, so its final byte sits at
  // limit + marker.length - 2.
  final wanted = limit + _pdfMarker.length - 1;
  final size = source.length < wanted ? source.length : wanted;
  if (size < _pdfMarker.length) return -1;
  final prefix = Uint8List(size);
  var filled = 0;
  while (filled < size) {
    final count = source.readInto(filled, prefix, filled, size - filled);
    if (count <= 0) break;
    filled += count;
  }
  if (filled < _pdfMarker.length) return -1;
  final scanned =
      filled == size ? prefix : Uint8List.sublistView(prefix, 0, filled);
  final ceiling = limit - 1;
  final pdf = _indexOfMarker(scanned, _pdfMarker, ceiling);
  if (pdf >= 0) return pdf;
  return _indexOfMarker(scanned, _fdfMarker, ceiling);
}

/// Offset that [sourceAtPdfHeader] would shift [source] by: zero when the
/// header already sits at byte zero, or when no header was found at all.
int pdfHeaderWindowStart(PdfByteSource source,
    {int limit = pdfHeaderSearchLimit}) {
  final start = findPdfHeaderOffset(source, limit: limit);
  return start > 0 ? start : 0;
}

/// Returns [source] repositioned so that position zero is the `%` of its
/// header.
///
/// [source] is returned unchanged when the header is already at byte zero or
/// when no header is present within [limit] bytes; a missing header stays the
/// caller's problem to report, so that an input which is not a PDF at all keeps
/// failing with the usual diagnostic.
PdfByteSource sourceAtPdfHeader(PdfByteSource source,
    {int limit = pdfHeaderSearchLimit}) {
  final start = pdfHeaderWindowStart(source, limit: limit);
  if (start == 0) return source;
  if (source is PdfMemorySource) {
    // A view over the same buffer: no copy, and the reader keeps its
    // memory-backed fast paths.
    return PdfMemorySource(Uint8List.sublistView(source.bytes, start));
  }
  return WindowedByteSource(source, start);
}
