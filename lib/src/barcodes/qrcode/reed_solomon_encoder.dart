import 'gf_256.dart';

/// Appends systematic QR error-correction symbols using a feedback register.
class CraftReedSolomonEncoder {
  final CraftGF256 _field;

  CraftReedSolomonEncoder(this._field) {
    if (!identical(_field, CraftGF256.QR_CODE_FIELD)) {
      throw ArgumentError('QR parity requires the field with modulus 0x11d.');
    }
  }

  /// Replaces the last [ecBytes] entries with parity; data entries are retained.
  void encode(List<int> toEncode, int ecBytes) {
    RangeError.checkValueInInterval(ecBytes, 1, 255, 'ecBytes');
    final payloadSize = toEncode.length - ecBytes;
    if (payloadSize < 1) {
      throw ArgumentError(
          'The parity buffer must follow at least one data byte.');
    }
    for (var index = 0; index < payloadSize; index++) {
      RangeError.checkValueInInterval(toEncode[index], 0, 255, 'data byte');
    }

    // Ascending coefficients of the product (x + 2^i), i = 0 .. ecBytes-1.
    var generator = <int>[1];
    var root = 1;
    for (var factor = 0; factor < ecBytes; factor++) {
      final expanded = List<int>.filled(generator.length + 1, 0);
      for (var degree = 0; degree < generator.length; degree++) {
        expanded[degree] ^= _field.multiply(generator[degree], root);
        expanded[degree + 1] ^= generator[degree];
      }
      generator = expanded;
      root = _field.multiply(root, 2);
    }

    final parity = List<int>.filled(ecBytes, 0);
    for (var index = 0; index < payloadSize; index++) {
      final feedback = toEncode[index] ^ parity[0];
      for (var slot = 0; slot < ecBytes; slot++) {
        final shifted = slot + 1 < ecBytes ? parity[slot + 1] : 0;
        parity[slot] =
            shifted ^ _field.multiply(feedback, generator[ecBytes - slot - 1]);
      }
    }
    toEncode.setRange(payloadSize, toEncode.length, parity);
  }
}
