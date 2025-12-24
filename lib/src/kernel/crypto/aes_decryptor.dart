import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/aes_cipher.dart';
import 'package:dpdf/src/kernel/crypto/i_decryptor.dart';

/// AES decryptor implementation.
class AesDecryptor implements IDecryptor {
  AESCipher? _cipher;
  final Uint8List _key;
  bool _initiated = false;
  final Uint8List _iv = Uint8List(16);
  int _ivptr = 0;

  AesDecryptor(Uint8List key, [int off = 0, int? len])
      : _key = Uint8List.fromList(
            key.sublist(off, off + (len ?? (key.length - off))));

  @override
  Uint8List? update(Uint8List b, int off, int len) {
    if (_initiated) {
      final res = _cipher!.update(b, off, len);
      return res.isEmpty ? null : res;
    } else {
      int left = math.min(_iv.length - _ivptr, len);
      _iv.setRange(_ivptr, _ivptr + left, b.sublist(off, off + left));
      off += left;
      len -= left;
      _ivptr += left;

      if (_ivptr == _iv.length) {
        _cipher = AESCipher(false, _key, _iv);
        _initiated = true;
        if (len > 0) {
          final res = _cipher!.update(b, off, len);
          return res.isEmpty ? null : res;
        }
      }
      return null;
    }
  }

  @override
  Uint8List? finish() {
    if (_cipher != null) {
      final res = _cipher!.doFinal();
      return res.isEmpty ? null : res;
    }
    return null;
  }
}
