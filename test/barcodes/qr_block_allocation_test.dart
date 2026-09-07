import 'package:dpdf/src/barcodes/qrcode/encoder.dart';
import 'package:dpdf/src/barcodes/qrcode/encode_hint_type.dart';
import 'package:dpdf/src/barcodes/qrcode/error_correction_level.dart';
import 'package:dpdf/src/barcodes/qrcode/qr_code.dart';
import 'package:dpdf/src/barcodes/qrcode/version.dart';
import 'package:test/test.dart';

void main() {
  for (final level in [
    ErrorCorrectionLevel.L,
    ErrorCorrectionLevel.M,
    ErrorCorrectionLevel.Q,
    ErrorCorrectionLevel.H
  ]) {
    test('all 40 versions allocate data and equal parity at level $level', () {
      for (var number = 1; number <= 40; number++) {
        final version = Version.getVersionForNumber(number);
        final correction = version.getECBlocksForLevel(level);
        final symbol = QRCode();
        Encoder.encode(
            'a', level, {EncodeHintType.MIN_VERSION_NR: number}, symbol);
        expect(symbol.formatVersion(), number, reason: 'version $number');
        expect(symbol.isValid(), isTrue);
        expect(symbol.getMatrixWidth(), 17 + 4 * number);
        var expectedData = 0;
        for (final group in correction.getECBlocks()) {
          expectedData += group.getCount() * group.getDataCodewords();
        }
        expect(symbol.getNumDataBytes(), expectedData);
        expect(symbol.getNumRSBlocks(), correction.getNumBlocks());
        expect(symbol.getNumECBytes(),
            correction.getNumBlocks() * correction.getECCodewordsPerBlock());
        expect(symbol.getNumTotalBytes(), version.getTotalCodewords());
      }
    });
  }
}
