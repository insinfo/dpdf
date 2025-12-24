import 'dart:typed_data';

/// RC4 encryption algorithm implementation.
class ARCFOUREncryption {
  final Uint8List _state = Uint8List(256);
  int _x = 0;
  int _y = 0;

  ARCFOUREncryption();

  void prepareARCFOURKey(Uint8List key, [int off = 0, int? len]) {
    final length = len ?? (key.length - off);
    int index1 = 0;
    int index2 = 0;
    for (int k = 0; k < 256; ++k) {
      _state[k] = k;
    }
    _x = 0;
    _y = 0;
    int tmp;
    for (int k = 0; k < 256; ++k) {
      index2 = (key[index1 + off] + _state[k] + index2) & 255;
      tmp = _state[k];
      _state[k] = _state[index2];
      _state[index2] = tmp;
      index1 = (index1 + 1) % length;
    }
  }

  void encryptARCFOUR(
      Uint8List dataIn, int off, int len, Uint8List dataOut, int offOut) {
    int length = len + off;
    int tmp;
    for (int k = off; k < length; ++k) {
      _x = (_x + 1) & 255;
      _y = (_state[_x] + _y) & 255;
      tmp = _state[_x];
      _state[_x] = _state[_y];
      _state[_y] = tmp;
      dataOut[k - off + offOut] =
          (dataIn[k] ^ _state[(_state[_x] + _state[_y]) & 255]) & 0xFF;
    }
  }

  void encryptARCFOURInPlace(Uint8List data, [int off = 0, int? len]) {
    final length = len ?? (data.length - off);
    encryptARCFOUR(data, off, length, data, off);
  }

  void encryptARCFOURAll(Uint8List dataToEncrypt, Uint8List dataOut) {
    encryptARCFOUR(dataToEncrypt, 0, dataToEncrypt.length, dataOut, 0);
  }
}
