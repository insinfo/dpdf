import 'dart:typed_data';
import '../commons/digest/digest_bytes.dart';

/// Legacy PKCS #12 derivation from RFC 7292, Appendix B.
abstract final class Pkcs12Derivation {
  /// Derives [length] bytes; purposes 1, 2 and 3 select key, IV and MAC material.
  /// Password code units use UTF-16BE followed by two zero bytes, including
  /// the empty password. Set [emptyPasswordIsZeroLength] only for legacy formats
  /// that encode an empty password without its terminator. Callers handling
  /// untrusted files must cap work factors.
  static Uint8List deriveSha1(
      {required String password,
      required Uint8List salt,
      required int iterations,
      required int purpose,
      required int length,
      bool emptyPasswordIsZeroLength = false}) {
    if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');
    RangeError.checkValueInInterval(purpose, 1, 3, 'purpose');
    RangeError.checkNotNegative(length, 'length');
    final output = Uint8List(length);
    if (length == 0) return output;
    final encoded = Uint8List(password.isEmpty && emptyPasswordIsZeroLength
        ? 0
        : password.length * 2 + 2);
    final view = ByteData.sublistView(encoded);
    for (var index = 0; index < password.length; index++) {
      view.setUint16(index * 2, password.codeUnitAt(index), Endian.big);
    }
    Uint8List expand(Uint8List bytes) => bytes.isEmpty
        ? Uint8List(0)
        : Uint8List.fromList(List.generate(((bytes.length + 63) ~/ 64) * 64,
            (index) => bytes[index % bytes.length]));
    final state = Uint8List.fromList([...expand(salt), ...expand(encoded)]);
    final input = Uint8List(64 + state.length)..fillRange(0, 64, purpose);
    var produced = 0;
    while (produced < length) {
      input.setRange(64, input.length, state);
      var digest = DigestBytes.compute('SHA1', input);
      for (var round = 1; round < iterations; round++) {
        digest = DigestBytes.compute('SHA1', digest);
      }
      final count = length - produced < 20 ? length - produced : 20;
      output.setRange(produced, produced + count, digest);
      produced += count;
      if (produced == length) break;
      for (var block = 0; block < state.length; block += 64) {
        var carry = 1;
        for (var index = 63; index >= 0; index--) {
          final sum = state[block + index] + digest[index % 20] + carry;
          state[block + index] = sum & 255;
          carry = sum >> 8;
        }
      }
    }
    return output;
  }
}
