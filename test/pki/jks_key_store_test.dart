import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as oracle;
import 'package:pdfcraft/src/pki/jks_key_store.dart';
import 'package:test/test.dart';

List<int> integer(int value, int width) => [
      for (var shift = (width - 1) * 8; shift >= 0; shift -= 8)
        (value >> shift) & 255
    ];
List<int> modified(String text) {
  final bytes = <int>[];
  for (final unit in text.codeUnits) {
    if (unit > 0 && unit < 128) {
      bytes.add(unit);
    } else if (unit < 2048) {
      bytes.addAll([0xc0 | unit >> 6, 0x80 | unit & 63]);
    } else {
      bytes.addAll(
          [0xe0 | unit >> 12, 0x80 | (unit >> 6) & 63, 0x80 | unit & 63]);
    }
  }
  return [...integer(bytes.length, 2), ...bytes];
}

Uint8List authenticate(List<int> body, String password) {
  final digest = oracle.sha1.convert([
    for (final unit in password.codeUnits) ...[unit >> 8, unit & 255],
    ...ascii.encode('Mighty Aphrodite'),
    ...body,
  ]).bytes;
  return Uint8List.fromList([...body, ...digest]);
}

List<int> trusted(String alias,
        {int version = 2, int timestamp = -1, String type = 'X.509'}) =>
    [
      ...integer(2, 4),
      ...modified(alias),
      ...integer(timestamp, 8),
      if (version == 2) ...modified(type),
      ...integer(3, 4),
      1,
      2,
      3,
    ];
Uint8List fixture(List<List<int>> entries,
        {int version = 2, String password = 'test'}) =>
    authenticate([
      ...integer(0xfeedfeed, 4),
      ...integer(version, 4),
      ...integer(entries.length, 4),
      ...entries.expand((v) => v),
    ], password);

void main() {
  test(
      'OpenJDK-generated JKS recovers the same PKCS8 bytes as the independent oracle',
      () {
    final store =
        JksKeyStore.read(base64.decode(oracleStore), password: 'storepass');
    expect(store.version, 2);
    expect(store.entries.keys, containsAll(['signing', 'trusted']));
    final key = store.entries['signing']! as JksPrivateKey;
    expect(key.recoverPkcs8('entrypass'), base64.decode(oraclePrivateKey));
    expect(key.certificateChain.length, 1);
    expect(key.certificateChain.first.type, 'X.509');
    expect(
        (store.entries['trusted']! as JksTrustedCertificate).certificate.bytes,
        key.certificateChain.first.bytes);
    expect(key.creationTimeUtc, isNotNull);
  });
  test('Container and entry passwords are independently authenticated', () {
    expect(
        () => JksKeyStore.read(base64.decode(oracleStore), password: 'wrong'),
        throwsFormatException);
    final store =
        JksKeyStore.read(base64.decode(oracleStore), password: 'storepass');
    final key = store.entries['signing']! as JksPrivateKey;
    expect(() => key.recoverPkcs8('storepass'), throwsFormatException);
    expect(() => key.recoverPkcs8('wrong'), throwsFormatException);
    expect(key.recoverPkcs8('entrypass'), base64.decode(oraclePrivateKey));
  });
  test('Altered data and truncated digest cannot expose entries', () {
    final tampered = base64.decode(oracleStore)..[30] ^= 1;
    expect(() => JksKeyStore.read(tampered, password: 'storepass'),
        throwsFormatException);
    expect(() => JksKeyStore.read(Uint8List(31), password: ''),
        throwsFormatException);
  });
  test('Version one trusted certificates use implicit X.509 type', () {
    final store = JksKeyStore.read(
        fixture([trusted('legacy', version: 1)], version: 1),
        password: 'test');
    final entry = store.entries['legacy']! as JksTrustedCertificate;
    expect(entry.certificate.type, 'X.509');
    expect(entry.certificate.bytes, [1, 2, 3]);
    expect(entry.timestampMilliseconds, -BigInt.one);
  });
  test(
      'Modified UTF8 handles NUL and supplementary aliases and Unicode passwords',
      () {
    const alias = 'a\u0000😀';
    const password = 'senha-ç-😀';
    final store = JksKeyStore.read(
        fixture([trusted(alias)], password: password),
        password: password);
    expect(store.entries.containsKey(alias), isTrue);
    expect(store.entries[alias]!.alias, alias);
  });
  test('Empty password and empty store are supported explicitly', () {
    expect(JksKeyStore.read(fixture([], password: ''), password: '').entries,
        isEmpty);
  });
  test('Unknown versions, duplicate aliases and trailing data reject', () {
    expect(() => JksKeyStore.read(fixture([], version: 3), password: 'test'),
        throwsUnsupportedError);
    expect(
        () => JksKeyStore.read(fixture([trusted('same'), trusted('same')]),
            password: 'test'),
        throwsFormatException);
    final body = fixture([]).sublist(0, 12);
    expect(
        () => JksKeyStore.read(authenticate([...body, 99], 'test'),
            password: 'test'),
        throwsFormatException);
  });
  test('Authenticated malformed entry lengths and UTF8 fail safely', () {
    final huge = [
      ...integer(2, 4),
      ...modified('x'),
      ...integer(0, 8),
      ...modified('X.509'),
      ...integer(0xffffffff, 4)
    ];
    expect(() => JksKeyStore.read(fixture([huge]), password: 'test'),
        throwsFormatException);
    final invalidUtf = [
      ...integer(2, 4),
      0,
      2,
      0xc1,
      0x81,
      ...integer(0, 8),
      ...modified('X.509'),
      ...integer(0, 4)
    ];
    expect(() => JksKeyStore.read(fixture([invalidUtf]), password: 'test'),
        throwsFormatException);
  });
  test('Encoded fields are defensively copied', () {
    final bytes = fixture([trusted('cert')]);
    final store = JksKeyStore.read(bytes, password: 'test');
    bytes.fillRange(0, bytes.length, 0);
    final certificate =
        (store.entries['cert']! as JksTrustedCertificate).certificate;
    certificate.bytes[0] = 99;
    expect(certificate.bytes, [1, 2, 3]);
    expect(() => store.entries.clear(), throwsUnsupportedError);
  });
}

// Synthetic fixture generated with the local OpenJDK keytool, not third-party
// corpus data. PKCS8 oracle exported through KeyStore.getKey(...).getEncoded().
const oracleStore =
    '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'
    '8m1PuCbFGZUPd5o8Ph2F';
const oraclePrivateKey =
    'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC3lZ/r/i3/mV7N8yiMF3xXueUdnbKK6QNxZxkbdMu6HI3B5UC9'
    'KhQOVrnNzvohQkLM7B6kSNLDo8nsBFWKKdhgnznLiOmgrSAtP8n4B08SGzKqs5Avl/3fiW9YcxINT7BWSJM0+3n11YlTn5H7Kzmu'
    '3H/xNmxlWYpn1d8uwTr6CJ4cLCgT/hBq46dw6hT42VohW2pz3eWDaGbh2ia054Vc1B1X34rVYwRkRcCnzRqImH95GWA1ngOZ/Oot'
    'Vkj7KOlngB5InasF8iyQZJcD/EP1G18BVelq/5R+EuBz9gQqCA+0jG/Saa4zsYkwBXgJnEHqAqkRDCG975bRn0Mp84TFAgMBAAEC'
    'ggEAAVlKkv/Lk7irPyUds6XKhpR5j/WkJawfl9ozj4WUp5nlGrsV9i3UduSBOfde1Ba6CepkMT3Nup098wt3G2xCSDdzQ8EOQl1z'
    'QpHY6IcZOB9WCHYIRak+tsE6PbKeu9VNjNy8pCOC2mEGwMQH3QoMwvGgyQNm2XnGcAvct2m5BrQ9S+81zuzN3QIwFvMefKZ6F3eS'
    'iIPcrBEnaTwaMglRAxkBe17aXwKVakh4B/Yw7MwwJDgK0QwwmhNDYE5gN5giqnrimkwtMjUAxAADXMt7xc2Xq+uY5xwn3i4rQzjy'
    'BGVjmLNF6sPkNmEt9weeLECOxmaiRdDz1tgmVIYcx1xe8wKBgQDAnIxo8Sp5AZY+ajRmCQAC3P7mgfDfvW9Jhr2xECY3IkQBANCV'
    'WTZ3KgfmDTLcPHwuuewz/4r3qsLMwz2c2elyWEjVa7mnR+FaVbUMJHfYbM91JGQh89wvf7VGdWZJESP50G/un3pHMcW9FWkDT3Xa'
    'QB9sF/a3tCWWRiqO64N/bwKBgQD0AI0CUhXlqqu61J8e+fhQpqIqC8SEFUjgieQjsT45Ae4snzAPWAtcpn+dO5S4lnwMefYgM2mh'
    'MX3tyv4TjlGrXiRdxEkJHv1uAeoZdpgOVmQeOdgWTvdHCpMQnWu3ManfFNQiin87RCvyReX8G1LI+0gp2/zf6Vzqp2YwIz4lCwKB'
    'gAJ+xK7jWOqCY8DhPVaJDU/8Lu0rh8ROPu/T6AcwL16NehYNPaaBplv61mlbiGoj+nPcgrvVtqYotydR7C1pAUYy8JabM6eAHeI+'
    's/65RjguiK160DVEZHjVDbMg+DdAGpg05A5SUJI1ids+OMMLN3qhVAbhdJfCpK4CsLBzSpvPAoGBAJBqhwsZlHZDhrLkx20pHCx4'
    'A8EJB/35LxIe6xWpAR/yoYptiZ97R/ZFYYCpVAPQpYko4mD6rQlH5rXIkIr4kCPya2nIFEY+vlbO8USy6ZqKzWUKbXf+suKsQpDx'
    '62AZF+a+SDRNbrKgTbZuYonNjjkAaRzFZK0OTP1hqNzS7yQzAoGAIpIxks4Pol1zj+jgW4ejPq53YBVqWaTIy7AJPujK48UpAnkP'
    'V/1ubbwwD7HAEBUAKC0w7kiP7tiXLCx30z+ZFrqbIRfBgzppVLfLBvTVMbYQ/U8niKGSYaXSyNInC41rY1pu3W00RplEBh5/koDL'
    'PjaKmOhNIMwM8xVxrmMKep4=';
