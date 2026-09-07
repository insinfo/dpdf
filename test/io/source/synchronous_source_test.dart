import 'dart:typed_data';

import 'package:pdfcraft/src/io/source/array_random_access_source.dart';
import 'package:pdfcraft/src/io/source/independent_random_access_source.dart';
import 'package:pdfcraft/src/io/source/random_access_source.dart';
import 'package:pdfcraft/src/io/source/thread_safe_random_access_source.dart';
import 'package:test/test.dart';

void main() {
  test('synchronous sources preserve partial reads and ownership', () {
    final CraftRandomAccessSource owner =
        CraftArrayRandomAccessSource(Uint8List.fromList([10, 20, 30]));
    final borrowed = CraftIndependentRandomAccessSource(owner);
    final forwarding = CraftThreadSafeRandomAccessSource(borrowed);
    final int length = forwarding.length();
    final int byte = forwarding.get(1);
    final buffer = Uint8List(4);
    final int count = forwarding.getRange(1, buffer, 1, 3);
    expect(length, 3);
    expect(byte, 20);
    expect(count, 2);
    expect(buffer, [0, 20, 30, 0]);
    expect(forwarding.get(3), -1);
    forwarding.close();
    expect(owner.get(0), 10);
    owner.close();
    expect(() => borrowed.get(0), throwsStateError);
  });
}
