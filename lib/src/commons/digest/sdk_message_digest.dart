import 'dart:typed_data';
import 'digest_bytes.dart';
import 'message_digest.dart';

/// Buffered digest adapter backed exclusively by local digest implementations.
/// Each successful digest resets input. Updates copy their bytes immediately.
class SdkMessageDigest implements MessageDigest {
  final String _name;
  final int _byteLength;
  final BytesBuilder _pending = BytesBuilder();

  SdkMessageDigest(String algorithmName)
      : _name = algorithmName,
        _byteLength = DigestBytes.compute(algorithmName, Uint8List(0)).length;

  @override
  String getAlgorithmName() => _name;
  @override
  int getDigestLength() => _byteLength;
  @override
  void update(Uint8List buf, int off, int len) {
    RangeError.checkValidRange(off, off + len, buf.length);
    _pending.add(Uint8List.sublistView(buf, off, off + len));
  }

  @override
  void updateAll(Uint8List buf) => update(buf, 0, buf.length);
  @override
  void reset() => _pending.clear();
  @override
  Uint8List digest() {
    final result = DigestBytes.compute(_name, _pending.toBytes());
    reset();
    return result;
  }

  @override
  Uint8List digestWithInput(Uint8List enc) {
    updateAll(enc);
    return digest();
  }
}
