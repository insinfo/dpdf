import 'dart:typed_data';

class PdfFormatException extends FormatException {
  const PdfFormatException(super.message);
}

/// Unsigned certificate serial represented without machine-integer truncation.
class CertificateSerial {
  final BigInt _value;
  CertificateSerial._(this._value);

  factory CertificateSerial.fromHex(String input) {
    final digits =
        input.startsWith(RegExp(r'0[xX]')) ? input.substring(2) : input;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(digits)) {
      throw const PdfFormatException(
          'Certificate serial requires hexadecimal digits');
    }
    return CertificateSerial._(BigInt.parse(digits, radix: 16));
  }
  factory CertificateSerial.fromDecimal(String input) {
    if (!RegExp(r'^[0-9]+$').hasMatch(input)) {
      throw const PdfFormatException(
          'Certificate serial requires unsigned decimal digits');
    }
    return CertificateSerial._(BigInt.parse(input));
  }

  /// Accepts a DER INTEGER TLV or unsigned integer content bytes.
  factory CertificateSerial.fromDerInteger(Uint8List input) {
    if (input.isEmpty)
      throw const PdfFormatException('Certificate serial is empty');
    var start = 0;
    var end = input.length;
    if (input.first == 2 && input.length > 1) {
      start = 2;
      var size = input[1];
      if (size >= 128) {
        final octets = size & 127;
        if (octets == 0 ||
            octets > 4 ||
            octets > input.length - start ||
            input[start] == 0) {
          throw const PdfFormatException('Invalid DER serial length');
        }
        size = 0;
        for (var i = 0; i < octets; i++) {
          size = size * 256 + input[start++];
        }
        if (size < 128)
          throw const PdfFormatException('Nonminimal DER serial length');
      }
      end = start + size;
      if (size == 0 || end != input.length || (input[start] & 128) != 0) {
        throw const PdfFormatException('Invalid unsigned DER INTEGER');
      }
      if (size > 1 && input[start] == 0 && input[start + 1] < 128) {
        throw const PdfFormatException('Redundant DER sign padding');
      }
    }
    var value = BigInt.zero;
    for (var index = start; index < end; index++) {
      value = (value << 8) + BigInt.from(input[index]);
    }
    return CertificateSerial._(value);
  }

  String get hex => _value.toRadixString(16);
  String get hexPrefixed => '0x$hex';
  String get decimal => _value.toString();
  Uint8List get rawBytes {
    final digits = hex.length.isOdd ? '0$hex' : hex;
    return Uint8List.fromList([
      for (var offset = 0; offset < digits.length; offset += 2)
        int.parse(digits.substring(offset, offset + 2), radix: 16),
    ]);
  }
}

CertificateSerial _serial(String text) =>
    text.startsWith(RegExp(r'0[xX]')) || RegExp(r'[a-fA-F]').hasMatch(text)
        ? CertificateSerial.fromHex(text)
        : CertificateSerial.fromDecimal(text);
String normalizeSerialToHex(String serial) => _serial(serial).hex;
String normalizeSerialToDecimal(String serial) => _serial(serial).decimal;
bool equalsSerial(String first, String second) =>
    normalizeSerialToHex(first) == normalizeSerialToHex(second);
