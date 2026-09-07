import 'dart:typed_data';

/// A byte slice from a percent-prefixed physical line.
class PdfPercentCommentLine {
  final int offset;
  final Uint8List bytes;
  PdfPercentCommentLine({required this.offset, required Uint8List bytes})
      : bytes = Uint8List.fromList(bytes);

  String toAsciiSafe() => String.fromCharCodes(
      bytes.map((byte) => byte >= 32 && byte <= 126 ? byte : 46));
  String toHex() =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

/// Scans physical lines; this does not parse PDF strings or stream boundaries.
List<PdfPercentCommentLine> extractPdfPercentCommentLines(Uint8List bytes,
    {bool startOfLineOnly = true}) {
  final result = <PdfPercentCommentLine>[];
  var start = 0;
  while (start < bytes.length) {
    var end = start;
    while (end < bytes.length && bytes[end] != 10 && bytes[end] != 13) {
      end++;
    }
    var marker = start;
    if (!startOfLineOnly) {
      while (marker < end && bytes[marker] != 37) {
        marker++;
      }
    }
    if (marker < end && bytes[marker] == 37) {
      result.add(PdfPercentCommentLine(
          offset: marker, bytes: Uint8List.sublistView(bytes, marker, end)));
    }
    start = end + 1;
    if (end < bytes.length &&
        bytes[end] == 13 &&
        start < bytes.length &&
        bytes[start] == 10) {
      start++;
    }
  }
  return result;
}

class PdfCommentSanitizationResult {
  final Uint8List bytes;
  final int scrubbedLineCount;
  PdfCommentSanitizationResult(this.bytes, this.scrubbedLineCount);
}

/// Blanks ASCII comments before the first PDF object without changing offsets.
/// Header and binary marker lines remain intact. Editing signed bytes can
/// invalidate a signature; this routine does not update or verify signatures.
PdfCommentSanitizationResult sanitizePdfLeadingPercentComments(
    Uint8List input) {
  final output = Uint8List.fromList(input);
  if (input.length < 5 || String.fromCharCodes(input.take(5)) != '%PDF-') {
    return PdfCommentSanitizationResult(output, 0);
  }
  var start = 0;
  var count = 0;
  while (start < input.length) {
    var end = start;
    while (end < input.length && input[end] != 10 && input[end] != 13) {
      end++;
    }
    final line = input.sublist(start, end);
    final blank = line
        .every((byte) => byte == 0 || byte == 9 || byte == 12 || byte == 32);
    if (!blank && (line.isEmpty || line.first != 37)) break;
    if (start > 0 &&
        line.isNotEmpty &&
        line.first == 37 &&
        line.every((byte) => byte < 128) &&
        String.fromCharCodes(line) != '%%EOF') {
      output.fillRange(start + 1, end, 32);
      count++;
    }
    start = end + 1;
    if (end < input.length &&
        input[end] == 13 &&
        start < input.length &&
        input[start] == 10) {
      start++;
    }
  }
  return PdfCommentSanitizationResult(output, count);
}
