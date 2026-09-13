import 'dart:typed_data';

import 'package:dpdf/src/io/source/pdf_byte_source.dart';
import 'package:dpdf/src/io/source/windowed_byte_source.dart';
import 'package:test/test.dart';

/// A source that never satisfies a read in one go, to prove that the header
/// scan keeps reading until it has the whole prefix.
class _DribblingSource implements PdfByteSource {
  final Uint8List bytes;
  final int chunk;
  int reads = 0;
  bool closed = false;

  /// [chunk] is the most bytes a single read hands back, which is what makes
  /// this source exercise the short-read path.
  _DribblingSource(this.bytes, {this.chunk = 7});

  @override
  int get length => bytes.length;

  @override
  int byteAt(int offset) => offset >= bytes.length ? -1 : bytes[offset];

  @override
  int readInto(int position, Uint8List target, int offset, int count) {
    reads++;
    if (count == 0) return 0;
    if (position >= bytes.length) return -1;
    var size = count < chunk ? count : chunk;
    if (position + size > bytes.length) size = bytes.length - position;
    target.setRange(offset, offset + size, bytes, position);
    return size;
  }

  @override
  void close() => closed = true;
}

Uint8List _prefixed(int junk, List<int> tail) {
  final builder = Uint8List(junk + tail.length);
  for (var index = 0; index < junk; index++) {
    builder[index] = 0x41 + (index % 26);
  }
  builder.setRange(junk, builder.length, tail);
  return builder;
}

Uint8List _body(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  group('findPdfHeaderOffset', () {
    test('reports zero when the header already starts the file', () {
      final source = PdfMemorySource(_body('%PDF-2.0\nrest'));
      expect(findPdfHeaderOffset(source), 0);
      expect(pdfHeaderWindowStart(source), 0);
    });

    test('finds a header pushed back by arbitrary bytes', () {
      for (final junk in [1, 9, 656, 1023]) {
        final source =
            PdfMemorySource(_prefixed(junk, _body('%PDF-2.0\nrest')));
        expect(findPdfHeaderOffset(source), junk, reason: 'junk=$junk');
      }
    });

    test('rejects a header that starts past the search limit', () {
      final source = PdfMemorySource(_prefixed(1024, _body('%PDF-2.0\nrest')));
      expect(findPdfHeaderOffset(source), -1);
      expect(pdfHeaderWindowStart(source), 0);
    });

    test('accepts an FDF header only when no PDF header is present', () {
      expect(
          findPdfHeaderOffset(PdfMemorySource(_prefixed(4, _body('%FDF-1.2')))),
          4);
      // A later %PDF- still wins over an earlier %FDF-, since a PDF header is
      // what the reader is really after.
      final mixed = PdfMemorySource(_body('%FDF-1.2 ... %PDF-2.0'));
      expect(findPdfHeaderOffset(mixed), 13);
    });

    test('returns -1 when there is no header at all', () {
      expect(findPdfHeaderOffset(PdfMemorySource(_body('no header here'))), -1);
      expect(findPdfHeaderOffset(PdfMemorySource(Uint8List(0))), -1);
      expect(findPdfHeaderOffset(PdfMemorySource(_body('%PD'))), -1);
    });

    test('tolerates a source that returns short reads', () {
      // The marker straddles a read boundary at every one of these sizes, and
      // a chunk of one byte is the degenerate case: the scan has to stitch
      // `%PDF-` together across five separate reads.
      for (final chunk in [1, 3, 7, 64]) {
        final source = _DribblingSource(
            _prefixed(300, _body('%PDF-1.7\nrest')),
            chunk: chunk);
        expect(findPdfHeaderOffset(source), 300, reason: 'chunk $chunk');
        expect(source.reads, greaterThan(1), reason: 'chunk $chunk');
      }
    });
  });

  group('WindowedByteSource', () {
    final full = Uint8List.fromList(List<int>.generate(100, (i) => i));

    test('presents the delegate shifted and shortened', () {
      final window = WindowedByteSource(PdfMemorySource(full), 30);
      expect(window.start, 30);
      expect(window.length, 70);
      expect(window.byteAt(0), 30);
      expect(window.byteAt(69), 99);
      expect(window.byteAt(70), -1);
      expect(window.byteAt(1000), -1);
    });

    test('clips a read to the end of the window', () {
      final window = WindowedByteSource(PdfMemorySource(full), 90);
      final target = Uint8List(32);
      expect(window.readInto(0, target, 0, 32), 10);
      expect(target.sublist(0, 10), List<int>.generate(10, (i) => 90 + i));
      expect(window.readInto(10, target, 0, 4), -1);
      expect(window.readInto(0, target, 0, 0), 0);
    });

    test('reads from a position relative to the window', () {
      final window = WindowedByteSource(PdfMemorySource(full), 10);
      final target = Uint8List(5);
      expect(window.readInto(5, target, 0, 5), 5);
      expect(target, [15, 16, 17, 18, 19]);
    });

    test('is empty, not negative, when the window starts past the end', () {
      final window = WindowedByteSource(PdfMemorySource(full), 500);
      expect(window.length, 0);
      expect(window.byteAt(0), -1);
      expect(window.readInto(0, Uint8List(4), 0, 4), -1);
    });

    test('rejects a negative start', () {
      expect(() => WindowedByteSource(PdfMemorySource(full), -1),
          throwsA(isA<RangeError>()));
    });

    test('closes the delegate only when it owns it', () {
      final owned = _DribblingSource(full);
      WindowedByteSource(owned, 1).close();
      expect(owned.closed, isTrue);

      final borrowed = _DribblingSource(full);
      WindowedByteSource(borrowed, 1, ownsSource: false).close();
      expect(borrowed.closed, isFalse);
    });
  });

  group('sourceAtPdfHeader', () {
    test('returns the very same source when nothing must be skipped', () {
      final source = PdfMemorySource(_body('%PDF-2.0\nrest'));
      expect(identical(sourceAtPdfHeader(source), source), isTrue);
    });

    test('returns the very same source when there is no header', () {
      final source = PdfMemorySource(_body('not a pdf'));
      expect(identical(sourceAtPdfHeader(source), source), isTrue);
    });

    test('keeps a memory source memory backed, without copying', () {
      final bytes = _prefixed(656, _body('%PDF-2.0\nrest'));
      final shifted = sourceAtPdfHeader(PdfMemorySource(bytes));
      expect(shifted, isA<PdfMemorySource>());
      expect(shifted.length, bytes.length - 656);
      expect(shifted.byteAt(0), 0x25);
      // A view over the original buffer, not a copy of it.
      final view = (shifted as PdfMemorySource).bytes;
      expect(view.offsetInBytes, bytes.offsetInBytes + 656);
      expect(view.lengthInBytes, bytes.lengthInBytes - 656);
      bytes[656] = 0x7A;
      expect(view[0], 0x7A);
    });

    test('wraps a non memory source in a window', () {
      final bytes = _prefixed(9, _body('%PDF-1.7\nrest'));
      final shifted = sourceAtPdfHeader(_DribblingSource(bytes));
      expect(shifted, isA<WindowedByteSource>());
      expect((shifted as WindowedByteSource).start, 9);
      expect(shifted.length, bytes.length - 9);
      expect(shifted.byteAt(0), 0x25);
    });
  });
}
