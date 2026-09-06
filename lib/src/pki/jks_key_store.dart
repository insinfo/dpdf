import 'dart:convert';
import 'dart:typed_data';

import '../commons/digest/digest_bytes.dart';
import '../sign/der_objects.dart';

/// Reads authenticated JKS v1/v2 containers entirely from memory.
/// Certificates remain encoded data; this reader does not establish PKI trust.
class JksKeyStore {
  final int version;

  /// Aliases are preserved exactly as encoded, without case conversion.
  final Map<String, JksEntry> entries;
  JksKeyStore._(this.version, Map<String, JksEntry> entries)
      : entries = Map.unmodifiable(entries);

  /// A password is always required, including the empty password when intended.
  /// Integrity is checked before any entries are exposed.
  factory JksKeyStore.read(Uint8List bytes,
      {required String password, int maximumBytes = 64 * 1024 * 1024}) {
    if (maximumBytes < 32)
      throw ArgumentError.value(maximumBytes, 'maximumBytes');
    if (bytes.length < 32 || bytes.length > maximumBytes) {
      throw FormatException(
          'JKS container length is outside the permitted range.');
    }
    final content = Uint8List.fromList(bytes.sublist(0, bytes.length - 20));
    final secret = _passwordBytes(password);
    try {
      final expected =
          _sha1([secret, ascii.encode('Mighty Aphrodite'), content]);
      if (!_equal(expected, bytes.sublist(bytes.length - 20))) {
        throw FormatException(
            'JKS integrity check failed: incorrect password or altered data.');
      }
    } finally {
      secret.fillRange(0, secret.length, 0);
    }
    final input = _JksInput(content);
    if (input.word() != 0xfeedfeed)
      throw FormatException('Input is not a JKS container.');
    final version = input.word();
    if (version != 1 && version != 2)
      throw UnsupportedError('Unsupported JKS version $version.');
    final count = input.word();
    if (count > input.remaining ~/ 18)
      throw FormatException('JKS entry count exceeds the available data.');
    final entries = <String, JksEntry>{};
    for (var index = 0; index < count; index++) {
      final type = input.word();
      final alias = input.text();
      final timestamp = input.timestamp();
      if (entries.containsKey(alias))
        throw FormatException('Duplicate JKS alias.');
      if (type == 2) {
        entries[alias] = JksTrustedCertificate._(
            alias, timestamp, _certificate(input, version));
      } else if (type == 1) {
        final protected = input.blob();
        final chainLength = input.word();
        if (chainLength > input.remaining ~/ (version == 1 ? 4 : 6)) {
          throw FormatException(
              'JKS certificate chain length exceeds the available data.');
        }
        final certificates = <JksCertificate>[];
        for (var certificate = 0; certificate < chainLength; certificate++) {
          certificates.add(_certificate(input, version));
        }
        entries[alias] =
            JksPrivateKey._(alias, timestamp, protected, certificates);
      } else {
        throw UnsupportedError('Unsupported JKS entry tag $type.');
      }
    }
    if (input.remaining != 0)
      throw FormatException('Unexpected data after JKS entries.');
    return JksKeyStore._(version, entries);
  }

  static JksCertificate _certificate(_JksInput input, int version) =>
      JksCertificate._(version == 1 ? 'X.509' : input.text(), input.blob());
}

sealed class JksEntry {
  final String alias;

  /// Signed 64-bit milliseconds, retained exactly on VM, JS and Wasm.
  final BigInt timestampMilliseconds;
  JksEntry._(this.alias, this.timestampMilliseconds);
  DateTime? get creationTimeUtc {
    if (timestampMilliseconds.abs() > BigInt.from(8640000000000000))
      return null;
    return DateTime.fromMillisecondsSinceEpoch(timestampMilliseconds.toInt(),
        isUtc: true);
  }
}

class JksCertificate {
  final String type;
  final Uint8List _bytes;
  JksCertificate._(this.type, Uint8List bytes)
      : _bytes = Uint8List.fromList(bytes);
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

class JksTrustedCertificate extends JksEntry {
  final JksCertificate certificate;
  JksTrustedCertificate._(String alias, BigInt time, this.certificate)
      : super._(alias, time);
}

class JksPrivateKey extends JksEntry {
  final Uint8List _protectedBytes;
  final List<JksCertificate> certificateChain;
  JksPrivateKey._(String alias, BigInt time, Uint8List protected,
      List<JksCertificate> chain)
      : _protectedBytes = Uint8List.fromList(protected),
        certificateChain = List.unmodifiable(chain),
        super._(alias, time);
  Uint8List get protectedBytes => Uint8List.fromList(_protectedBytes);

  /// Recovers authenticated PKCS#8 bytes protected by the JKS SHA-1 scheme.
  /// The entry password can differ from the container password. Other protection
  /// algorithms are rejected; no fallback password or unauthenticated output exists.
  Uint8List recoverPkcs8(String password) {
    final envelope = ASN1Parser(_protectedBytes).readSingle();
    if (envelope is! ASN1Sequence || envelope.elements!.length != 2) {
      throw FormatException(
          'JKS protected key must be an EncryptedPrivateKeyInfo sequence.');
    }
    final algorithm = envelope.elements![0];
    final encoded = envelope.elements![1];
    if (algorithm is! ASN1Sequence ||
        algorithm.elements!.isEmpty ||
        algorithm.elements!.length > 2 ||
        algorithm.elements!.first is! ASN1ObjectIdentifier ||
        (algorithm.elements!.length == 2 &&
            algorithm.elements![1] is! ASN1Null) ||
        encoded is! ASN1OctetString) {
      throw FormatException('Malformed JKS key protection parameters.');
    }
    if ((algorithm.elements!.first as ASN1ObjectIdentifier)
            .objectIdentifierAsString !=
        '1.3.6.1.4.1.42.2.17.1.1') {
      throw UnsupportedError('JKS key protection algorithm is unsupported.');
    }
    final protected = encoded.octets;
    if (protected.length <= 40)
      throw FormatException('JKS protected key is truncated.');
    final secret = _passwordBytes(password);
    final clear = Uint8List(protected.length - 40);
    var chain = Uint8List.fromList(protected.sublist(0, 20));
    var success = false;
    try {
      for (var offset = 0; offset < clear.length; offset++) {
        if (offset % 20 == 0) chain = _sha1([secret, chain]);
        clear[offset] = protected[offset + 20] ^ chain[offset % 20];
      }
      if (!_equal(
          _sha1([secret, clear]), protected.sublist(protected.length - 20))) {
        throw FormatException('JKS private key authentication failed.');
      }
      final key = ASN1Parser(clear).readSingle();
      if (key is! ASN1Sequence ||
          key.elements!.length < 3 ||
          key.elements![0] is! ASN1Integer ||
          key.elements![1] is! ASN1Sequence ||
          key.elements![2] is! ASN1OctetString) {
        throw FormatException('Recovered JKS key is not a PKCS#8 private key.');
      }
      success = true;
      return clear;
    } finally {
      secret.fillRange(0, secret.length, 0);
      chain.fillRange(0, chain.length, 0);
      if (!success) clear.fillRange(0, clear.length, 0);
    }
  }
}

Uint8List _passwordBytes(String password) => Uint8List.fromList([
      for (final unit in password.codeUnits) ...[unit >> 8, unit & 255],
    ]);
Uint8List _sha1(Iterable<List<int>> pieces) {
  final buffer = BytesBuilder(copy: false);
  for (final piece in pieces) {
    buffer.add(piece);
  }
  return DigestBytes.compute('SHA-1', buffer.takeBytes());
}
bool _equal(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var index = 0; index < first.length; index++)
    difference |= first[index] ^ second[index];
  return difference == 0;
}

class _JksInput {
  final Uint8List bytes;
  int position = 0;
  _JksInput(this.bytes);
  int get remaining => bytes.length - position;
  Uint8List take(int length) {
    if (length < 0 || length > remaining)
      throw FormatException('JKS field extends beyond its container.');
    final result = Uint8List.sublistView(bytes, position, position + length);
    position += length;
    return result;
  }

  int word() => ByteData.sublistView(take(4)).getUint32(0);
  Uint8List blob() => take(word());
  BigInt timestamp() {
    final data = take(8);
    var result = BigInt.zero;
    for (final byte in data) result = (result << 8) + BigInt.from(byte);
    return data.first >= 128 ? result - (BigInt.one << 64) : result;
  }

  String text() {
    final data = take(ByteData.sublistView(take(2)).getUint16(0));
    final units = <int>[];
    var index = 0;
    while (index < data.length) {
      final lead = data[index++];
      if (lead > 0 && lead < 128) {
        units.add(lead);
        continue;
      }
      final extra = lead >= 0xc0 && lead <= 0xdf
          ? 1
          : lead >= 0xe0 && lead <= 0xef
              ? 2
              : -1;
      if (extra < 0 || index + extra > data.length)
        throw FormatException('Malformed JKS modified UTF-8 string.');
      var unit = lead & (extra == 1 ? 31 : 15);
      for (var part = 0; part < extra; part++) {
        final next = data[index++];
        if (next & 0xc0 != 0x80)
          throw FormatException('Malformed JKS UTF-8 continuation.');
        unit = unit * 64 + (next & 63);
      }
      if ((extra == 1 && unit < 128 && unit != 0) ||
          (extra == 2 && unit < 0x800)) {
        throw FormatException('Noncanonical JKS modified UTF-8 string.');
      }
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }
}
