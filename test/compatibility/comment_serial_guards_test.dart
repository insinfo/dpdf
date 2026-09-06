import 'dart:convert';
import 'dart:typed_data';
import 'package:pdfcraft/src/compatibility/pdf_percent_comments.dart';
import 'package:pdfcraft/src/compatibility/certificate_serial.dart';
import 'package:test/test.dart';

void main() {
  test('scrubbing preserves binary marker, CRLF, source and post-object data',
      () {
    final input = Uint8List.fromList([
      ...latin1.encode('%PDF-1.7\r\n'),
      37,
      200,
      201,
      202,
      203,
      13,
      10,
      ...latin1.encode('%private\r\n1 0 obj\r\n%keep\r\n'),
    ]);
    final original = Uint8List.fromList(input);
    final result = sanitizePdfLeadingPercentComments(input);
    expect(input, original);
    expect(result.bytes.length, input.length);
    expect(result.scrubbedLineCount, 1);
    expect(result.bytes.sublist(10, 17), input.sublist(10, 17));
    expect(latin1.decode(result.bytes), endsWith('1 0 obj\r\n%keep\r\n'));
  });
  test('physical lines preserve offsets across CR, LF and CRLF', () {
    final lines = extractPdfPercentCommentLines(
        Uint8List.fromList(latin1.encode('%a\r%b\n%c\r\n%d')));
    expect(lines.map((line) => line.offset), [0, 3, 6, 10]);
  });
  test('DER serial rejects negative, truncated and nonminimal forms', () {
    for (final input in [
      [2, 1, 128],
      [2, 2, 1],
      [2, 0],
      [2, 0x81, 1, 1],
      [2, 2, 0, 1]
    ]) {
      expect(() => CertificateSerial.fromDerInteger(Uint8List.fromList(input)),
          throwsA(isA<PdfFormatException>()));
    }
  });
}
