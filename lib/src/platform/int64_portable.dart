import 'dart:typed_data';

BigInt signedWord64(ByteData data, int offset, Endian endian) {
  var value = BigInt.zero;
  for (var index = 0; index < 8; index++) {
    value = (value << 8) +
        BigInt.from(
            data.getUint8(offset + (endian == Endian.big ? index : 7 - index)));
  }
  return value.toSigned(64);
}
