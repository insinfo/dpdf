import 'package:pdfcraft/src/barcodes/qrcode/format_information.dart';
import 'package:pdfcraft/src/barcodes/qrcode/qr_code_writer.dart';
import 'package:test/test.dart';

void main() {
  test('format recovery honors correction radius and either physical copy', () {
    const word = 0x77c4; // L, mask zero.
    for (var a = 0; a < 15; a++) {
      for (var b = a + 1; b < 15; b++) {
        for (var c = b + 1; c < 15; c++) {
          final noisy = word ^ (1 << a) ^ (1 << b) ^ (1 << c);
          final decoded =
              CraftFormatInformation.decodeFormatInformation(noisy, noisy)!;
          expect(decoded.getDataMask(), 0);
          expect(decoded.getErrorCorrectionLevel().bits, 1);
        }
      }
    }
    expect(
        CraftFormatInformation.decodeFormatInformation(0, word)?.getDataMask(),
        0);
    expect(CraftFormatInformation.numBitsDiffering(-1, 0), 32);
  });
  test(
      'writer preserves integer scaling and quiet zone in a rectangular raster',
      () {
    final writer = CraftQRCodeWriter();
    final small = writer.encode('ABC', 0, 0);
    final large = writer.encode('ABC', 90, 60);
    expect(small.getWidth(), 29);
    expect(large.getWidth(), 90);
    expect(large.getHeight(), 60);
    for (var y = 0; y < 60; y++) {
      for (var x = 0; x < 90; x++) {
        final inside = x >= 24 && x < 66 && y >= 9 && y < 51;
        final expected =
            inside ? small.get(4 + (x - 24) ~/ 2, 4 + (y - 9) ~/ 2) : 255;
        expect(large.get(x, y), expected);
      }
    }
    expect(() => writer.encode('', 0, 0), throwsArgumentError);
  });
}
