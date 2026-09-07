import 'dart:typed_data';
import 'package:dpdf/dpdf.dart';
import 'package:pointycastle/export.dart' as oracle;
import 'package:test/test.dart';

Uint8List octets(List<int> values) => Uint8List.fromList(values);
Uint8List word(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();
Uint8List blob(List<int> value) => octets([...word(value.length), ...value]);
// Test wire encoder, independent of the library's writer.
List<int> text(String value) {
  final bytes = <int>[];
  for (final unit in value.codeUnits) {
    if (unit > 0 && unit < 128) {
      bytes.add(unit);
    } else if (unit < 2048) {
      bytes.addAll([192 + (unit ~/ 64), 128 + unit % 64]);
    } else {
      bytes.addAll(
          [224 + unit ~/ 4096, 128 + (unit ~/ 64) % 64, 128 + unit % 64]);
    }
  }
  return [bytes.length ~/ 256, bytes.length % 256, ...bytes];
}

final salt = octets([1, 8, 2, 7, 3, 6, 4, 5]);
final cert = octets(
    [0x30, 3, 2, 1, 7]); // synthetic ASN.1 payload, not an actual trust anchor
Uint8List derive(String password, int purpose, int length) {
  final encoded = octets([
    for (final unit in password.codeUnits) ...[unit >> 8, unit & 255],
    if (password.isNotEmpty) ...[0, 0]
  ]);
  final generator = oracle.PKCS12ParametersGenerator(oracle.SHA1Digest())
    ..init(encoded, salt, 7);
  return purpose == 1
      ? generator.generateDerivedParameters(length).key
      : purpose == 2
          ? generator.generateDerivedParametersWithIV(1, length).iv
          : generator.generateDerivedMacParameters(length).key;
}

Uint8List fixture(List<int> body, {String password = 'senha'}) {
  final data = octets(body);
  final mac = oracle.HMac(oracle.SHA1Digest(), 64)
    ..init(oracle.KeyParameter(derive(password, 3, 20)));
  return octets(
      [...word(2), ...blob(salt), ...word(7), ...data, ...mac.process(data)]);
}

List<int> recordHeader(int type, String alias) =>
    [type, ...text(alias), ...List.filled(8, 0), ...word(0)];
List<int> encodedCert() => [...text('X.509'), ...blob(cert)];
List<int> keyData() =>
    [2, ...text('RAW'), ...text('AES'), ...blob(List.generate(16, (i) => i))];

void main() {
  test('reads independently authenticated certificate and re-encodes it', () {
    final input = fixture([...recordHeader(1, 'raiz'), ...encodedCert(), 0]);
    final store = BksKeyStore.decode(input, password: 'senha');
    expect(store.version, 2);
    expect(store.records.single.alias, 'raiz');
    expect(store.certificates.single.bytes, cert);
    expect(store.records.single.createdAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    expect(store.encode(password: 'senha'), input);
  });
  test(
      'accepts empty password and modified UTF8 aliases including null and supplementary units',
      () {
    const alias = 'raiz\u0000漢😀';
    final store = BksKeyStore.decode(
        fixture([...recordHeader(1, alias), ...encodedCert(), 0], password: ''),
        password: '');
    expect(store.records.single.alias, alias);
    expect(
        BksKeyStore.decode(store.encode(password: ''), password: '')
            .records
            .single
            .alias,
        alias);
  });
  test('reads raw key kind, format, algorithm and opaque secret', () {
    final store = BksKeyStore.decode(
        fixture([
          ...recordHeader(2, 'key'),
          ...keyData(),
          ...recordHeader(3, 'opaque'),
          ...blob([9, 8, 7]),
          0
        ]),
        password: 'senha');
    expect(store.records.first.key!.kind, 2);
    expect(store.records.first.key!.format, 'RAW');
    expect(store.records.first.key!.algorithm, 'AES');
    expect(store.records.first.recoverKey('unused').bytes,
        List.generate(16, (i) => i));
    expect(store.records.last.payload, [9, 8, 7]);
  });
  test('recovers sealed key encrypted by independent Triple DES implementation',
      () {
    const keyPassword = 'entry-password';
    final cipher = oracle.PaddedBlockCipherImpl(
        oracle.PKCS7Padding(), oracle.CBCBlockCipher(oracle.DESedeEngine()))
      ..init(
          true,
          oracle.PaddedBlockCipherParameters<
                  oracle.ParametersWithIV<oracle.KeyParameter>, Null>(
              oracle.ParametersWithIV(
                  oracle.KeyParameter(derive(keyPassword, 1, 24)),
                  derive(keyPassword, 2, 8)),
              null));
    final encrypted = cipher.process(octets(keyData()));
    final sealed = [...blob(salt), ...word(7), ...encrypted];
    final store = BksKeyStore.decode(
        fixture([...recordHeader(4, 'sealed'), ...blob(sealed), 0]),
        password: 'senha');
    expect(store.records.single.recoverKey(keyPassword).bytes,
        List.generate(16, (i) => i));
    expect(
        () => store.records.single.recoverKey('wrong'), throwsFormatException);
    expect(() => store.records.single.recoverKey(keyPassword, maxIterations: 6),
        throwsFormatException);
  });
  test('reports malformed sealed payloads as input errors', () {
    for (final payload in <List<int>>[
      [],
      [...blob(salt), ...word(7)],
      [...blob(salt), ...word(7), 1],
    ]) {
      final store = BksKeyStore.decode(
          fixture([...recordHeader(4, 'bad'), ...blob(payload), 0]),
          password: 'senha');
      expect(() => store.records.single.recoverKey('key-password'),
          throwsFormatException);
    }
  });
  test('rejects wrong password and tampering', () {
    final data = fixture([...recordHeader(1, 'a'), ...encodedCert(), 0]);
    expect(() => BksKeyStore.decode(data, password: 'wrong'),
        throwsFormatException);
    data[data.length - 1] ^= 1;
    expect(() => BksKeyStore.decode(data, password: 'senha'),
        throwsFormatException);
  });
  test('rejects truncated inputs at every byte boundary', () {
    final data = fixture([...recordHeader(1, 'a'), ...encodedCert(), 0]);
    for (var i = 0; i < data.length; i++) {
      expect(
          () =>
              BksKeyStore.decode(octets(data.sublist(0, i)), password: 'senha'),
          throwsFormatException,
          reason: 'offset $i');
    }
  });
  test('rejects authenticated malformed record structures', () {
    for (final body in <List<int>>[
      [5, 0],
      [0, 1],
      [...recordHeader(1, 'a'), ...encodedCert()],
      [
        ...recordHeader(1, 'a'),
        ...encodedCert(),
        ...recordHeader(1, 'a'),
        ...encodedCert(),
        0
      ],
      [
        ...recordHeader(2, 'a'),
        3,
        ...text('RAW'),
        ...text('AES'),
        ...blob([1]),
        0
      ],
      [1, 0, 1, 0, 0],
    ]) {
      expect(() => BksKeyStore.decode(fixture(body), password: 'senha'),
          throwsFormatException);
    }
  });
  test('limits KDF work and rejects unsupported store versions', () {
    final data = fixture([0]);
    expect(() => BksKeyStore.decode(data, password: 'senha', maxIterations: 6),
        throwsFormatException);
    data[3] = 1;
    expect(() => BksKeyStore.decode(data, password: 'senha'),
        throwsUnsupportedError);
  });
  test('creates stores and preserves certificate chains and pre-epoch dates',
      () {
    final chain = BksCertificate('X.509', cert);
    final store = BksKeyStore.create(salt: salt, iterations: 7, records: [
      BksRecord(
          alias: 'a',
          createdAt: DateTime.utc(1960),
          kind: BksRecordKind.certificate,
          certificate: chain,
          chain: [chain])
    ]);
    final parsed =
        BksKeyStore.decode(store.encode(password: 'senha'), password: 'senha');
    expect(parsed.certificates.length, 2);
    expect(parsed.records.single.createdAt, DateTime.utc(1960));
  });
}
