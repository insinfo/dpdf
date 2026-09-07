import 'dart:math';
import 'dart:typed_data';
import 'package:dpdf/src/platform/int64.dart' as selected;
import 'package:dpdf/src/platform/int64_js.dart' as js;
import 'package:dpdf/src/platform/int64_portable.dart' as portable;
import 'package:test/test.dart';

void main() {
  test('target word loaders agree for signs, offsets and byte orders', () {
    final random = Random(42);
    for (var iteration = 0; iteration < 1000; iteration++) {
      final bytes =
          Uint8List.fromList(List.generate(12, (_) => random.nextInt(256)));
      final data = ByteData.sublistView(bytes);
      for (final endian in [Endian.big, Endian.little]) {
        final expected = portable.signedWord64(data, 2, endian);
        expect(js.signedWord64(data, 2, endian), expected);
        expect(selected.signedWord64(data, 2, endian), expected);
      }
    }
  });
}
