import 'dart:typed_data';

/// VM and Wasm support a direct signed 64-bit typed-data load.
BigInt signedWord64(ByteData data, int offset, Endian endian) =>
    BigInt.from(data.getInt64(offset, endian));
