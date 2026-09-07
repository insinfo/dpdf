import 'dart:math';
import 'dart:typed_data';
import '../commons/digest/digest_bytes.dart';
import '../sign/der_objects.dart';

abstract class PublicKey {}

abstract class PrivateKey {}

class RSAPublicKey implements PublicKey {
  final BigInt modulus;
  final BigInt exponent;
  RSAPublicKey(this.modulus, this.exponent) {
    if (modulus <= BigInt.from(3) ||
        modulus.isEven ||
        exponent < BigInt.from(3) ||
        exponent.isEven ||
        exponent >= modulus) {
      throw ArgumentError('Invalid RSA public modulus or exponent');
    }
  }
}

class RSAPrivateKey implements PrivateKey {
  final BigInt modulus;
  final BigInt exponent;
  final BigInt? p, q;
  BigInt get privateExponent => exponent;
  RSAPrivateKey(this.modulus, this.exponent, this.p, this.q);
}

class AsymmetricKeyPair<P extends PublicKey, S extends PrivateKey> {
  final P publicKey;
  final S privateKey;
  AsymmetricKeyPair(this.publicKey, this.privateKey);
}

class RSASignature {
  final Uint8List bytes;
  RSASignature(this.bytes);
}

class PublicKeyParameter<T extends PublicKey> {
  final T key;
  PublicKeyParameter(this.key);
}

class PrivateKeyParameter<T extends PrivateKey> {
  final T key;
  PrivateKeyParameter(this.key);
}

/// RSASSA-PKCS1-v1_5, as specified by RFC 8017 section 8.2.
class Signer {
  final String algorithm;
  RSAPublicKey? _public;
  RSAPrivateKey? _private;
  Signer(this.algorithm) {
    if (!algorithm.toUpperCase().endsWith('/RSA')) {
      throw UnsupportedError('Unsupported signature algorithm: $algorithm');
    }
    _encoding(Uint8List(0));
  }
  void init(bool signing, dynamic parameter) {
    _public = null;
    _private = null;
    if (signing) {
      _private = (parameter as PrivateKeyParameter).key as RSAPrivateKey;
    } else {
      _public = (parameter as PublicKeyParameter).key as RSAPublicKey;
    }
  }

  Uint8List _encoding(Uint8List data) {
    final name = algorithm.split('/').first.toUpperCase().replaceAll('-', '');
    const oids = {
      'MD2': '1.2.840.113549.2.2',
      'RIPEMD128': '1.3.36.3.2.2',
      'RIPEMD160': '1.3.36.3.2.1',
      'RIPEMD256': '1.3.36.3.2.3',
      'SHA224': '2.16.840.1.101.3.4.2.4',
      'MD5': '1.2.840.113549.2.5',
      'SHA1': '1.3.14.3.2.26',
      'SHA256': '2.16.840.1.101.3.4.2.1',
      'SHA384': '2.16.840.1.101.3.4.2.2',
      'SHA512': '2.16.840.1.101.3.4.2.3'
    };
    final oid = oids[name];
    if (oid == null) throw UnsupportedError('Unsupported RSA digest $name');
    return ASN1Sequence(elements: [
      ASN1Sequence(elements: [
        ASN1ObjectIdentifier.fromIdentifierString(oid),
        ASN1Null()
      ]),
      ASN1OctetString(octets: DigestBytes.compute(name, data))
    ]).encode();
  }

  Uint8List _em(Uint8List data, int length) {
    final digestInfo = _encoding(data);
    if (length < digestInfo.length + 11) {
      throw ArgumentError('RSA key too small for digest');
    }
    return Uint8List.fromList([
      0,
      1,
      ...List.filled(length - digestInfo.length - 3, 255),
      0,
      ...digestInfo
    ]);
  }

  RSASignature generateSignature(Uint8List data) {
    final key = _private;
    if (key == null) throw StateError('Signer has no private key');
    final size = (key.modulus.bitLength + 7) ~/ 8;
    final m = RsaMath.decode(_em(data, size));
    // Multiplicative message blinding reduces input-dependent timing leakage.
    final publicExponent = key.p != null && key.q != null
        ? key.exponent.modInverse((key.p! - BigInt.one) * (key.q! - BigInt.one))
        : null;
    BigInt signature;
    if (publicExponent != null) {
      BigInt r;
      do {
        r = RsaMath.randomBelow(key.modulus);
      } while (r < BigInt.two || r.gcd(key.modulus) != BigInt.one);
      final blinded = (m * r.modPow(publicExponent, key.modulus)) % key.modulus;
      signature = (blinded.modPow(key.exponent, key.modulus) *
              r.modInverse(key.modulus)) %
          key.modulus;
    } else {
      signature = m.modPow(key.exponent, key.modulus);
    }
    return RSASignature(RsaMath.encode(signature, size));
  }

  bool verifySignature(Uint8List data, RSASignature signature) {
    final key = _public;
    if (key == null) throw StateError('Signer has no public key');
    final size = (key.modulus.bitLength + 7) ~/ 8;
    if (signature.bytes.length != size) return false;
    final s = RsaMath.decode(signature.bytes);
    if (s >= key.modulus) return false;
    final actual = RsaMath.encode(s.modPow(key.exponent, key.modulus), size);
    final expected = _em(data, size);
    var difference = 0;
    for (var i = 0; i < size; i++) {
      difference |= actual[i] ^ expected[i];
    }
    return difference == 0;
  }
}

abstract final class RsaMath {
  static final _random = Random.secure();
  static Uint8List randomBytes(int count) =>
      Uint8List.fromList(List.generate(count, (_) => _random.nextInt(256)));
  static BigInt decode(List<int> bytes) {
    var n = BigInt.zero;
    for (final b in bytes) {
      n = (n << 8) | BigInt.from(b);
    }
    return n;
  }

  static Uint8List encode(BigInt value, int length) {
    final out = Uint8List(length);
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (value & BigInt.from(255)).toInt();
      value >>= 8;
    }
    if (value != BigInt.zero) throw ArgumentError('Integer does not fit');
    return out;
  }

  static BigInt randomBelow(BigInt limit) {
    if (limit <= BigInt.zero) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive');
    }
    final bits = limit.bitLength;
    final size = (bits + 7) ~/ 8;
    while (true) {
      final b = randomBytes(size);
      b[0] &= 255 >> (size * 8 - bits);
      final n = decode(b);
      if (n < limit) return n;
    }
  }

  static bool _prime(BigInt n) {
    for (final p in [
      2,
      3,
      5,
      7,
      11,
      13,
      17,
      19,
      23,
      29,
      31,
      37,
      41,
      43,
      47,
      53,
      59,
      61,
      67,
      71,
      73,
      79,
      83,
      89,
      97
    ]) {
      final b = BigInt.from(p);
      if (n == b) return true;
      if (n % b == BigInt.zero) return false;
    }
    var d = n - BigInt.one, s = 0;
    while (d.isEven) {
      d >>= 1;
      s++;
    }
    for (var round = 0; round < 64; round++) {
      final a = randomBelow(n - BigInt.from(3)) + BigInt.two;
      var x = a.modPow(d, n);
      if (x == BigInt.one || x == n - BigInt.one) continue;
      var passed = false;
      for (var i = 1; i < s; i++) {
        x = (x * x) % n;
        if (x == n - BigInt.one) {
          passed = true;
          break;
        }
      }
      if (!passed) return false;
    }
    return true;
  }

  static BigInt _generatePrime(int bits, BigInt e) {
    while (true) {
      final b = randomBytes((bits + 7) ~/ 8);
      b[0] &= 255 >> (b.length * 8 - bits);
      b[0] |= 1 << ((bits - 1) % 8);
      b[b.length - 1] |= 1;
      final n = decode(b);
      if ((n - BigInt.one).gcd(e) == BigInt.one && _prime(n)) return n;
    }
  }

  static AsymmetricKeyPair<PublicKey, PrivateKey> generate(int bits) {
    if (bits < 512) throw ArgumentError('RSA requires at least 512 bits');
    final e = BigInt.from(65537);
    while (true) {
      final p = _generatePrime(bits ~/ 2, e),
          q = _generatePrime(bits - bits ~/ 2, e);
      final n = p * q;
      if (p == q || n.bitLength != bits) continue;
      final d = e.modInverse((p - BigInt.one) * (q - BigInt.one));
      return AsymmetricKeyPair(RSAPublicKey(n, e), RSAPrivateKey(n, d, p, q));
    }
  }
}
