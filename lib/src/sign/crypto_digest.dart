import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'i_external_digest.dart';

/// Implementation of message digest using Dart's crypto package.
class CryptoMessageDigest implements IMessageDigest {
  final String _algorithmName;
  final List<int> _buffer = [];

  CryptoMessageDigest._(this._algorithmName);

  /// Creates a message digest for SHA-1.
  factory CryptoMessageDigest.sha1() => CryptoMessageDigest._('SHA-1');

  /// Creates a message digest for SHA-256.
  factory CryptoMessageDigest.sha256() => CryptoMessageDigest._('SHA-256');

  /// Creates a message digest for SHA-384.
  factory CryptoMessageDigest.sha384() => CryptoMessageDigest._('SHA-384');

  /// Creates a message digest for SHA-512.
  factory CryptoMessageDigest.sha512() => CryptoMessageDigest._('SHA-512');

  /// Creates a message digest for MD5.
  factory CryptoMessageDigest.md5() => CryptoMessageDigest._('MD5');

  @override
  void update(Uint8List input, [int offset = 0, int? length]) {
    final len = length ?? (input.length - offset);
    if (offset == 0 && len == input.length) {
      _buffer.addAll(input);
    } else {
      _buffer.addAll(input.sublist(offset, offset + len));
    }
  }

  @override
  Uint8List digest() {
    final data = Uint8List.fromList(_buffer);
    _buffer.clear();

    Digest result;
    switch (_algorithmName.toUpperCase()) {
      case 'SHA-1':
      case 'SHA1':
        result = sha1.convert(data);
        break;
      case 'SHA-256':
      case 'SHA256':
        result = sha256.convert(data);
        break;
      case 'SHA-384':
      case 'SHA384':
        result = sha384.convert(data);
        break;
      case 'SHA-512':
      case 'SHA512':
        result = sha512.convert(data);
        break;
      case 'MD5':
        result = md5.convert(data);
        break;
      default:
        throw UnsupportedError('Unsupported digest algorithm: $_algorithmName');
    }
    return Uint8List.fromList(result.bytes);
  }

  @override
  String getAlgorithmName() => _algorithmName;

  @override
  int getDigestSize() {
    switch (_algorithmName.toUpperCase()) {
      case 'SHA-1':
      case 'SHA1':
        return 20;
      case 'SHA-256':
      case 'SHA256':
        return 32;
      case 'SHA-384':
      case 'SHA384':
        return 48;
      case 'SHA-512':
      case 'SHA512':
        return 64;
      case 'MD5':
        return 16;
      default:
        throw UnsupportedError('Unsupported digest algorithm: $_algorithmName');
    }
  }

  @override
  void reset() {
    _buffer.clear();
  }
}

/// Implementation of IExternalDigest using Dart's crypto package.
///
/// TODO: Consider using pointycastle for more algorithms (RIPEMD160, SHA3, etc.)
class CryptoDigest implements IExternalDigest {
  const CryptoDigest();

  @override
  IMessageDigest getMessageDigest(String hashAlgorithm) {
    final algo = hashAlgorithm.toUpperCase().replaceAll('-', '');
    switch (algo) {
      case 'SHA1':
        return CryptoMessageDigest.sha1();
      case 'SHA256':
        return CryptoMessageDigest.sha256();
      case 'SHA384':
        return CryptoMessageDigest.sha384();
      case 'SHA512':
        return CryptoMessageDigest.sha512();
      case 'MD5':
        return CryptoMessageDigest.md5();
      default:
        throw UnsupportedError('Unsupported hash algorithm: $hashAlgorithm');
    }
  }
}
