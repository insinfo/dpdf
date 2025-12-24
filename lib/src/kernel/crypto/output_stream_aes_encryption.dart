import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/aes_cipher.dart';
import 'package:dpdf/src/kernel/crypto/iv_generator.dart';
import 'package:dpdf/src/kernel/crypto/output_stream_encryption.dart';
import 'package:dpdf/src/kernel/exceptions/kernel_exception_message_constant.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';

/// AES encryption output stream.
class OutputStreamAesEncryption extends OutputStreamEncryption {
  late AESCipher _cipher;
  bool _finished = false;

  OutputStreamAesEncryption(dynamic output, Uint8List key,
      [int off = 0, int? len])
      : super(output) {
    final iv = IVGenerator.getIV();
    final nkey =
        Uint8List.fromList(key.sublist(off, off + (len ?? (key.length - off))));
    _cipher = AESCipher(true, nkey, iv);

    try {
      _writeToOutput(iv);
    } catch (e) {
      throw PdfException(KernelExceptionMessageConstant.unknownPdfException,
          cause: e);
    }
  }

  @override
  void write(Uint8List b, [int off = 0, int? len]) {
    final length = len ?? (b.length - off);
    final b2 = _cipher.update(b, off, length);
    if (b2.isNotEmpty) {
      _writeToOutput(b2);
    }
  }

  @override
  void finish() {
    if (!_finished) {
      _finished = true;
      final b = _cipher.doFinal();
      if (b.isNotEmpty) {
        _writeToOutput(b);
      }
    }
  }

  void _writeToOutput(Uint8List bytes) {
    if (output is Sink<List<int>>) {
      (output as Sink<List<int>>).add(bytes);
    } else if (output is BytesBuilder) {
      (output as BytesBuilder).add(bytes);
    } else {
      throw Exception("Unsupported output type for OutputStreamAesEncryption");
    }
  }
}
