import 'dart:typed_data';
import 'package:dpdf/src/io/source/byte_utils.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';

import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

/// PdfOutputStream class represents an algorithm for writing data into content stream.
class PdfOutputStream {
  final Sink<List<int>>? _sink;
  final BytesBuilder? _builder;

  // Cache standard bytes
  static final Uint8List _space = Uint8List.fromList([32]);
  static final Uint8List _newline = Uint8List.fromList([10]);

  PdfOutputStream(Sink<List<int>> sink)
      : _sink = sink,
        _builder = null;

  PdfOutputStream.fromBuilder(BytesBuilder builder)
      : _builder = builder,
        _sink = null;

  /// Writes a single byte.
  void writeByte(int b) {
    if (_builder != null) {
      _builder.addByte(b);
    } else {
      _sink!.add([b]);
    }
  }

  /// Writes a list of bytes.
  void writeBytes(List<int> b) {
    if (_builder != null) {
      _builder.add(b);
    } else {
      _sink!.add(b);
    }
  }

  /// Writes a string as ISO-8859-1 bytes.
  void writeString(String s) {
    writeBytes(ByteUtils.getIsoBytes(s));
  }

  /// Writes an integer.
  void writeInteger(int n) {
    writeBytes(ByteUtils.getIsoBytesFromInt(n));
  }

  /// Writes a double.
  void writeDouble(double d) {
    writeBytes(ByteUtils.getIsoBytesFromDouble(d));
  }

  /// Writes a float (same as double in Dart).
  void writeFloat(double f) {
    writeDouble(f);
  }

  /// Writes a space character.
  void writeSpace() {
    writeBytes(_space);
  }

  /// Writes a newline character.
  void writeNewLine() {
    writeBytes(_newline);
  }

  /// Writes a PDF Name.
  void writePdfName(PdfName name) {
    writeByte(47); // /
    writeString(name.getValue());
  }

  /// Writes a PdfString.
  void writePdfStringObject(PdfString pdfString) {
    if (pdfString.isHexWriting()) {
      writeByte(60); // <
      final bytes = pdfString.getValueBytes();
      if (bytes != null) {
        for (final b in bytes) {
          final hex = b.toRadixString(16).toUpperCase().padLeft(2, '0');
          writeString(hex);
        }
      }
      writeByte(62); // >
    } else {
      writeByte(40); // (
      final bytes = pdfString.getValueBytes();
      if (bytes != null) {
        for (final b in bytes) {
          if (b == 40 || b == 41 || b == 92) {
            // ( ) \
            writeByte(92);
          }
          writeByte(b);
        }
      }
      writeByte(41); // )
    }
  }
}
