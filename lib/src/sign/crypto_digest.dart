import 'dart:typed_data';
import '../commons/digest/digest_bytes.dart';
import 'external_digest.dart';

/// Incremental input collection for the local PDF digest implementations.
class CryptoMessageDigest implements SigningDigest {
  final String _algorithmName;
  final int _size;
  final BytesBuilder _input = BytesBuilder();

  CryptoMessageDigest._(this._algorithmName, this._size);
  factory CryptoMessageDigest.sha1() => CryptoMessageDigest._('SHA-1', 20);
  factory CryptoMessageDigest.sha256() => CryptoMessageDigest._('SHA-256', 32);
  factory CryptoMessageDigest.sha384() => CryptoMessageDigest._('SHA-384', 48);
  factory CryptoMessageDigest.sha512() => CryptoMessageDigest._('SHA-512', 64);
  factory CryptoMessageDigest.md5() => CryptoMessageDigest._('MD5', 16);

  @override
  void update(Uint8List input, [int offset = 0, int? length]) {
    final end = offset + (length ?? input.length - offset);
    RangeError.checkValidRange(offset, end, input.length);
    _input.add(Uint8List.sublistView(input, offset, end));
  }

  @override
  Uint8List digest() => DigestBytes.compute(_algorithmName, _input.takeBytes());

  @override
  String getAlgorithmName() => _algorithmName;

  @override
  int getDigestSize() => _size;

  @override
  void reset() => _input.clear();
}

/// Selects supported SDK-only digests without loading an external provider.
class CryptoDigest implements ExternalDigest {
  const CryptoDigest();

  static const _algorithms = <String, (String, int)>{
    'MD2': ('MD2', 16),
    'MD5': ('MD5', 16),
    'SHA1': ('SHA-1', 20),
    'SHA224': ('SHA-224', 28),
    'SHA256': ('SHA-256', 32),
    'SHA384': ('SHA-384', 48),
    'SHA512': ('SHA-512', 64),
    'RIPEMD128': ('RIPEMD128', 16),
    'RIPEMD160': ('RIPEMD160', 20),
    'RIPEMD256': ('RIPEMD256', 32),
    'SHA3224': ('SHA3-224', 28),
    'SHA3256': ('SHA3-256', 32),
    'SHA3384': ('SHA3-384', 48),
    'SHA3512': ('SHA3-512', 64),
    'SHAKE128': ('SHAKE128', 32),
    'SHAKE256': ('SHAKE256', 64),
  };

  @override
  SigningDigest getMessageDigest(String hashAlgorithm) {
    final key = hashAlgorithm.toUpperCase().replaceAll(RegExp(r'[-/]'), '');
    final specification = _algorithms[key];
    if (specification == null) {
      throw UnsupportedError(
          'No PDF digest implementation for $hashAlgorithm.');
    }
    return CryptoMessageDigest._(specification.$1, specification.$2);
  }
}
