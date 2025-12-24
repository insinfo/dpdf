import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// AES cipher implementation using PointyCastle.
/// Supports CBC mode and optional PKCS7 padding.
class AESCipher {
  final BlockCipher _cipher;
  final bool _encrypt;
  final bool _usePadding;
  final Uint8List _buffer = Uint8List(16);
  int _bufferPtr = 0;

  AESCipher(bool encrypt, Uint8List key, Uint8List iv, {bool usePadding = true})
      : _cipher = CBCBlockCipher(AESEngine()),
        _encrypt = encrypt,
        _usePadding = usePadding {
    _cipher.init(encrypt, ParametersWithIV(KeyParameter(key), iv));
  }

  /// Processes chunks of data.
  Uint8List update(Uint8List input, int inputOffset, int inputLen) {
    int remaining = inputLen;
    int currentOffset = inputOffset;
    final out = <int>[];

    while (remaining > 0) {
      if (_bufferPtr < 16) {
        int toCopy = 16 - _bufferPtr;
        if (toCopy > remaining) toCopy = remaining;
        _buffer.setRange(_bufferPtr, _bufferPtr + toCopy,
            input.sublist(currentOffset, currentOffset + toCopy));
        _bufferPtr += toCopy;
        currentOffset += toCopy;
        remaining -= toCopy;
      }

      if (_bufferPtr == 16) {
        // If encrypting, we can process immediately.
        // If decrypting, if we use padding, we must save the last block for doFinal.
        if (_encrypt || !_usePadding || remaining > 0) {
          final blockOut = Uint8List(16);
          _cipher.processBlock(_buffer, 0, blockOut, 0);
          out.addAll(blockOut);
          _bufferPtr = 0;
        }
      }
    }
    return Uint8List.fromList(out);
  }

  /// Finishes the operation and handles padding.
  Uint8List doFinal() {
    final out = <int>[];
    if (_encrypt) {
      if (_usePadding) {
        // PKCS7 padding
        int paddingValue = 16 - _bufferPtr;
        for (int i = _bufferPtr; i < 16; i++) {
          _buffer[i] = paddingValue;
        }
        final blockOut = Uint8List(16);
        _cipher.processBlock(_buffer, 0, blockOut, 0);
        out.addAll(blockOut);
      } else if (_bufferPtr > 0) {
        // No padding but buffer not empty
        throw Exception(
            "Encryption error: data length not a multiple of block size");
      }
    } else {
      // For decryption, if usePadding is true, _buffer should contain the last block
      if (_bufferPtr != 16 && _usePadding) {
        throw Exception("Decryption error: last block incomplete");
      }

      if (_bufferPtr > 0) {
        final blockOut = Uint8List(16);
        _cipher.processBlock(_buffer, 0, blockOut, 0);

        if (_usePadding) {
          // Remove PKCS7 padding
          int paddingValue = blockOut[15];
          if (paddingValue < 1 || paddingValue > 16) {
            throw Exception("Decryption error: invalid padding");
          }
          out.addAll(blockOut.sublist(0, 16 - paddingValue));
        } else {
          out.addAll(blockOut);
        }
      }
    }
    _bufferPtr = 0;
    return Uint8List.fromList(out);
  }

  /// Utility to process a whole block directly (mimics iText's ProcessBlock)
  Uint8List processBlock(Uint8List input, int offset, int length) {
    if (length % 16 != 0) {
      throw Exception(
          "ProcessBlock error: input length must be multiple of 16");
    }
    final out = Uint8List(length);
    for (int i = 0; i < length; i += 16) {
      _cipher.processBlock(input, offset + i, out, i);
    }
    return out;
  }
}
