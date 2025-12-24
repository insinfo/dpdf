import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;
import 'package:dpdf/src/commons/digest/i_message_digest.dart';

/// Implementation of IMessageDigest using PointyCastle.
class PointyCastleDigest implements IMessageDigest {
  final pc.Digest _digest;
  final String _algorithmName;

  PointyCastleDigest(this._algorithmName) : _digest = pc.Digest(_algorithmName);

  @override
  Uint8List digest() {
    final result = Uint8List(_digest.digestSize);
    _digest.doFinal(result, 0);
    return result;
  }

  @override
  Uint8List digestWithInput(Uint8List enc) {
    _digest.update(enc, 0, enc.length);
    return digest();
  }

  @override
  String getAlgorithmName() => _algorithmName;

  @override
  int getDigestLength() => _digest.digestSize;

  @override
  void reset() {
    _digest.reset();
  }

  @override
  void update(Uint8List buf, int off, int len) {
    _digest.update(buf, off, len);
  }

  @override
  void updateAll(Uint8List buf) {
    _digest.update(buf, 0, buf.length);
  }
}
