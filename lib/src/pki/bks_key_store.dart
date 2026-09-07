import 'dart:math';
import 'dart:typed_data';
import '../commons/digest/digest_bytes.dart';
import 'pkcs12_derivation.dart';
import 'triple_des.dart';

/// An encoded certificate, not a statement of trust or certificate validity.
class BksCertificate {
  final String format;
  final Uint8List bytes;
  BksCertificate(this.format, List<int> bytes)
      : bytes = Uint8List.fromList(bytes);
}

/// The original key encoding: 0 private, 1 public, 2 symmetric.
class BksKeyMaterial {
  final int kind;
  final String format;
  final String algorithm;
  final Uint8List bytes;
  BksKeyMaterial(this.kind, this.format, this.algorithm, List<int> bytes)
      : bytes = Uint8List.fromList(bytes);
}

enum BksRecordKind { certificate, key, opaqueSecret, sealedKey }

class BksRecord {
  final String alias;
  final DateTime createdAt;
  final List<BksCertificate> chain;
  final BksRecordKind kind;
  final BksCertificate? certificate;
  final BksKeyMaterial? key;
  final Uint8List? payload;

  BksRecord(
      {required this.alias,
      required this.createdAt,
      required this.kind,
      List<BksCertificate> chain = const [],
      this.certificate,
      this.key,
      List<int>? payload})
      : chain = List.unmodifiable(chain),
        payload = payload == null ? null : Uint8List.fromList(payload);

  /// Recovers a standard BKS sealed key. The entry password can differ from
  /// the store password. Legacy broken PBE variants are not attempted.
  BksKeyMaterial recoverKey(String password, {int maxIterations = 1000000}) {
    if (kind == BksRecordKind.key) return key!;
    if (kind != BksRecordKind.sealedKey) {
      throw StateError('This record does not contain a recoverable key.');
    }
    final input = _Input(payload!);
    final salt = input.blob(limit: 4096);
    final iterations = input.u32();
    _iterations(iterations, maxIterations);
    if (salt.isEmpty) throw FormatException('Sealed key salt is empty.');
    if (input.remaining == 0 || input.remaining % 8 != 0) {
      throw FormatException(
          'Sealed key does not contain complete cipher blocks.');
    }
    final encryptionKey = Pkcs12Derivation.deriveSha1(
        emptyPasswordIsZeroLength: true,
        password: password,
        salt: salt,
        iterations: iterations,
        purpose: 1,
        length: 24);
    final iv = Pkcs12Derivation.deriveSha1(
        emptyPasswordIsZeroLength: true,
        password: password,
        salt: salt,
        iterations: iterations,
        purpose: 2,
        length: 8);
    try {
      final plain = TripleDes.decryptCbc(input.take(input.remaining),
          key: encryptionKey, iv: iv);
      try {
        final decoded = _Input(plain);
        final material = decoded.key();
        decoded.end();
        return material;
      } finally {
        plain.fillRange(0, plain.length, 0);
      }
    } finally {
      encryptionKey.fillRange(0, encryptionKey.length, 0);
    }
  }
}

/// BKS v2 reader/writer. Integrity is always checked before exposing entries.
/// Callers supply bytes so the same API works in VM, JavaScript and Wasm.
class BksKeyStore {
  final List<BksRecord> records;
  final Uint8List salt;
  final int iterations;
  int get version => 2;
  BksKeyStore._(this.records, this.salt, this.iterations);

  factory BksKeyStore.create(
      {List<BksRecord> records = const [],
      int iterations = 2048,
      Uint8List? salt}) {
    _iterations(iterations, 1000000);
    final random = salt == null ? Random.secure() : null;
    final chosen = salt ??
        Uint8List.fromList(List.generate(20, (_) => random!.nextInt(256)));
    if (chosen.isEmpty || chosen.length > 4096) {
      throw ArgumentError('Salt length must be 1..4096.');
    }
    return BksKeyStore._(
        List.unmodifiable(records), Uint8List.fromList(chosen), iterations);
  }

  static BksKeyStore decode(Uint8List bytes,
      {required String password,
      int maxIterations = 1000000,
      int maximumBytes = 64 * 1024 * 1024}) {
    if (maximumBytes < 33) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes');
    }
    if (bytes.length > maximumBytes) {
      throw FormatException('Store exceeds the accepted size.');
    }
    final header = _Input(bytes);
    final version = header.u32();
    if (version != 2) throw UnsupportedError('Only BKS version 2 is accepted.');
    final salt = header.blob(limit: 4096);
    if (salt.isEmpty) throw FormatException('Store salt is empty.');
    final iterations = header.u32();
    _iterations(iterations, maxIterations);
    if (header.remaining < 21) {
      throw FormatException('Store body or integrity tag is missing.');
    }
    final body = header.take(header.remaining - 20);
    final tag = header.take(20);
    final expected = _mac(body, password, salt, iterations);
    var difference = 0;
    for (var i = 0; i < 20; i++) {
      difference |= tag[i] ^ expected[i];
    }
    if (difference != 0) {
      throw FormatException('Store password or integrity check failed.');
    }
    final input = _Input(body);
    final records = <BksRecord>[];
    final aliases = <String>{};
    while (true) {
      final type = input.u8();
      if (type == 0) break;
      if (type > 4) throw FormatException('Unknown store record type.');
      if (records.length >= 100000) {
        throw FormatException('Store has too many records.');
      }
      final alias = input.text();
      if (!aliases.add(alias)) throw FormatException('Store repeats an alias.');
      final date = input.date();
      final count = input.u32();
      if (count > 10000 || count > input.remaining ~/ 6) {
        throw FormatException('Invalid chain size.');
      }
      final chain = List.generate(count, (_) => input.certificate());
      records.add(BksRecord(
          alias: alias,
          createdAt: date,
          kind: BksRecordKind.values[type - 1],
          chain: chain,
          certificate: type == 1 ? input.certificate() : null,
          key: type == 2 ? input.key() : null,
          payload: type >= 3 ? input.blob() : null));
    }
    input.end();
    return BksKeyStore._(List.unmodifiable(records), salt, iterations);
  }

  Iterable<BksCertificate> get certificates sync* {
    for (final record in records) {
      if (record.certificate != null) yield record.certificate!;
      yield* record.chain;
    }
  }

  /// Rewrites records with a store MAC. Sealed key bytes retain their separate
  /// entry password; changing this password does not re-encrypt those keys.
  Uint8List encode({required String password}) {
    final body = _Output();
    final aliases = <String>{};
    for (final record in records) {
      if (!aliases.add(record.alias)) {
        throw ArgumentError('Duplicate store alias.');
      }
      body.u8(record.kind.index + 1);
      body.text(record.alias);
      body.date(record.createdAt);
      body.u32(record.chain.length);
      for (final certificate in record.chain) {
        body.certificate(certificate);
      }
      switch (record.kind) {
        case BksRecordKind.certificate:
          if (record.certificate == null) {
            throw ArgumentError('Certificate record has no certificate.');
          }
          body.certificate(record.certificate!);
        case BksRecordKind.key:
          if (record.key == null) throw ArgumentError('Key record has no key.');
          final key = record.key!;
          if (key.kind < 0 || key.kind > 2) {
            throw ArgumentError('Invalid key kind.');
          }
          body.u8(key.kind);
          body.text(key.format);
          body.text(key.algorithm);
          body.blob(key.bytes);
        case BksRecordKind.opaqueSecret:
        case BksRecordKind.sealedKey:
          if (record.payload == null) {
            throw ArgumentError('Record has no payload.');
          }
          body.blob(record.payload!);
      }
    }
    body.u8(0);
    final data = body.bytes.takeBytes();
    final output = _Output()
      ..u32(2)
      ..blob(salt)
      ..u32(iterations);
    output.bytes.add(data);
    output.bytes.add(_mac(data, password, salt, iterations));
    return output.bytes.takeBytes();
  }
}

void _iterations(int value, int limit) {
  if (limit < 1) throw ArgumentError.value(limit, 'maxIterations');
  if (value < 1 || value > limit) {
    throw FormatException('KDF iteration count exceeds the accepted range.');
  }
}

Uint8List _mac(
    Uint8List body, String password, Uint8List salt, int iterations) {
  final key = Pkcs12Derivation.deriveSha1(
      emptyPasswordIsZeroLength: true,
      password: password,
      salt: salt,
      iterations: iterations,
      purpose: 3,
      length: 20);
  final inner = Uint8List(64 + body.length)
    ..setRange(64, 64 + body.length, body);
  final outer = Uint8List(84);
  for (var i = 0; i < 64; i++) {
    final value = i < key.length ? key[i] : 0;
    inner[i] = value ^ 0x36;
    outer[i] = value ^ 0x5c;
  }
  outer.setRange(64, 84, DigestBytes.compute('SHA1', inner));
  final result = DigestBytes.compute('SHA1', outer);
  key.fillRange(0, key.length, 0);
  inner.fillRange(0, inner.length, 0);
  outer.fillRange(0, outer.length, 0);
  return result;
}

class _Input {
  final Uint8List bytes;
  int offset = 0;
  _Input(this.bytes);
  int get remaining => bytes.length - offset;
  Uint8List take(int size) {
    if (size < 0 || size > remaining) {
      throw FormatException('Truncated store field.', null, offset);
    }
    final data =
        Uint8List.fromList(Uint8List.sublistView(bytes, offset, offset + size));
    offset += size;
    return data;
  }

  int u8() {
    if (remaining == 0) throw FormatException('Unexpected end of store.');
    return bytes[offset++];
  }

  int u32() => ByteData.sublistView(take(4)).getUint32(0);
  Uint8List blob({int limit = 67108864}) {
    final size = u32();
    if (size > limit) throw FormatException('Store field exceeds size limit.');
    return take(size);
  }

  String text() {
    final length = u8() * 256 + u8();
    final encoded = _Input(take(length));
    final units = <int>[];
    while (encoded.remaining > 0) {
      final a = encoded.u8();
      if (a > 0 && a < 128) {
        units.add(a);
        continue;
      }
      if (a >= 0xc0 && a <= 0xdf) {
        final b = encoded.u8();
        if ((b & 0xc0) != 0x80) {
          throw FormatException('Invalid text continuation.');
        }
        final unit = (a & 31) * 64 + (b & 63);
        if (unit < 128 && unit != 0) {
          throw FormatException('Overlong store text.');
        }
        units.add(unit);
        continue;
      }
      if (a >= 0xe0 && a <= 0xef) {
        final b = encoded.u8(), c = encoded.u8();
        if ((b & 0xc0) != 0x80 || (c & 0xc0) != 0x80) {
          throw FormatException('Invalid text continuation.');
        }
        final unit = (a & 15) * 4096 + (b & 63) * 64 + (c & 63);
        if (unit < 2048) throw FormatException('Overlong store text.');
        units.add(unit);
        continue;
      }
      throw FormatException('Invalid modified UTF-8 text.');
    }
    return String.fromCharCodes(units);
  }

  DateTime date() {
    final data = take(8);
    var value = BigInt.zero;
    for (final byte in data) {
      value = (value << 8) | BigInt.from(byte);
    }
    if (data.first >= 128) value -= BigInt.one << 64;
    if (value.abs() > BigInt.from(8640000000000000)) {
      throw FormatException('Store timestamp is outside the supported range.');
    }
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }

  BksCertificate certificate() => BksCertificate(text(), blob());
  BksKeyMaterial key() {
    final kind = u8();
    if (kind > 2) throw FormatException('Unknown key kind.');
    return BksKeyMaterial(kind, text(), text(), blob());
  }

  void end() {
    if (remaining != 0) {
      throw FormatException('Unexpected bytes after the store terminator.');
    }
  }
}

class _Output {
  final bytes = BytesBuilder(copy: false);
  void u8(int value) => bytes.addByte(value);
  void u32(int value) {
    if (value < 0 || value > 0xffffffff) throw ArgumentError.value(value);
    bytes.add((ByteData(4)..setUint32(0, value)).buffer.asUint8List());
  }

  void blob(Uint8List value) {
    u32(value.length);
    bytes.add(value);
  }

  void text(String value) {
    final encoded = BytesBuilder();
    for (final unit in value.codeUnits) {
      if (unit > 0 && unit < 128) {
        encoded.addByte(unit);
      } else if (unit < 2048) {
        encoded.add([0xc0 | (unit >> 6), 0x80 | (unit & 63)]);
      } else {
        encoded.add([
          0xe0 | (unit >> 12),
          0x80 | ((unit >> 6) & 63),
          0x80 | (unit & 63)
        ]);
      }
    }
    final data = encoded.takeBytes();
    if (data.length > 65535) {
      throw ArgumentError('Encoded store text is too long.');
    }
    bytes.add([data.length >> 8, data.length & 255]);
    bytes.add(data);
  }

  void date(DateTime date) {
    var value = BigInt.from(date.millisecondsSinceEpoch).toUnsigned(64);
    final data = Uint8List(8);
    for (var i = 7; i >= 0; i--) {
      data[i] = (value & BigInt.from(255)).toInt();
      value >>= 8;
    }
    bytes.add(data);
  }

  void certificate(BksCertificate value) {
    text(value.format);
    blob(value.bytes);
  }
}
