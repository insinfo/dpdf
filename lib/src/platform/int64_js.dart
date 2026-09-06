import 'dart:typed_data';

/// JS combines exact 32-bit halves instead of rounding a 64-bit Number.
BigInt signedWord64(ByteData data, int offset, Endian endian) {
  final high = data.getInt32(offset + (endian == Endian.big ? 0 : 4), endian);
  final low = data.getUint32(offset + (endian == Endian.big ? 4 : 0), endian);
  return (BigInt.from(high) << 32) + BigInt.from(low);
}
