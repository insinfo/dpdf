import 'dart:typed_data';

import 'package:dpdf/src/io/source/byte_utils.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';

import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_literal.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_null.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_primitive_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

/// PdfOutputStream class represents an algorithm for writing data into content stream.
class PdfOutputStream {
  final Sink<List<int>>? _sink;
  final BytesBuilder? _builder;
  int _currentPos = 0;

  /// Document associated with PdfOutputStream.
  PdfDocument? document;

  // Crypto field for compatibility/future use
  // PdfEncryption? crypto; // Uncomment if imported
  dynamic crypto; // Placeholder to resolve TODO without adding deps loop

  // Cache standard bytes
  static final Uint8List _space = Uint8List.fromList([32]);
  static final Uint8List _newline = Uint8List.fromList([10]);
  static final Uint8List _openDict = Uint8List.fromList([60, 60]); // <<
  static final Uint8List _closeDict = Uint8List.fromList([62, 62]); // >>
  static final Uint8List _stream = ByteUtils.getIsoBytes("stream\n");
  static final Uint8List _endstream = ByteUtils.getIsoBytes("\nendstream");

  PdfOutputStream(Sink<List<int>> sink)
      : _sink = sink,
        _builder = null;

  PdfOutputStream.fromBuilder(BytesBuilder builder)
      : _builder = builder,
        _sink = null;

  /// Gets current position in the stream.
  int getCurrentPos() => _currentPos;

  /// Writes a single byte.
  void writeByte(int b) {
    if (_builder != null) {
      _builder.addByte(b);
    } else {
      _sink!.add([b]);
    }
    _currentPos++;
  }

  /// Writes a list of bytes.
  void writeBytes(List<int> b) {
    if (_builder != null) {
      _builder.add(b);
    } else {
      _sink!.add(b);
    }
    _currentPos += b.length;
  }

  /// Writes a string as ISO-8859-1 bytes.
  void writeString(String s) {
    writeBytes(ByteUtils.getIsoBytes(s));
  }

  /// Writes an integer.
  PdfOutputStream writeInteger(int n) {
    writeBytes(ByteUtils.getIsoBytesFromInt(n));
    return this;
  }

  /// Writes a long (represented as int in Dart).
  PdfOutputStream writeLong(int n) {
    writeString(n.toString());
    return this;
  }

  /// Writes a double.
  PdfOutputStream writeDouble(double d) {
    writeBytes(ByteUtils.getIsoBytesFromDouble(d));
    return this;
  }

  /// Writes a float (same as double in Dart).
  PdfOutputStream writeFloat(double f) {
    writeDouble(f);
    return this;
  }

  /// Writes a space character.
  PdfOutputStream writeSpace() {
    writeBytes(_space);
    return this;
  }

  /// Writes a newline character.
  void writeNewLine() {
    writeBytes(_newline);
  }

  /// Write a PdfObject to the outputstream.
  Future<PdfOutputStream> writePdfObject(PdfObject pdfObject) async {
    if (pdfObject.checkState(PdfObject.mustBeIndirect) && document != null) {
      pdfObject.makeIndirect(document!);
      pdfObject = pdfObject.getIndirectReference()!;
    }

    switch (pdfObject.getObjectType()) {
      case PdfObjectType.array:
        await _writeArray(pdfObject as PdfArray);
        break;
      case PdfObjectType.dictionary:
        await _writeDictionary(pdfObject as PdfDictionary);
        break;
      case PdfObjectType.indirectReference:
        writeIndirectReference(pdfObject as PdfIndirectReference);
        break;
      case PdfObjectType.name:
        writePdfName(pdfObject as PdfName);
        break;
      case PdfObjectType.nullType:
      case PdfObjectType.boolean:
        writePrimitive(pdfObject as PdfPrimitiveObject);
        break;
      case PdfObjectType.literal:
        writeLiteral(pdfObject as PdfLiteral);
        break;
      case PdfObjectType.string:
        writePdfStringObject(pdfObject as PdfString);
        break;
      case PdfObjectType.number:
        writePdfNumber(pdfObject as PdfNumber);
        break;
      case PdfObjectType.stream:
        await _writePdfStream(pdfObject as PdfStream);
        break;
    }
    return this;
  }

  void writePrimitive(PdfPrimitiveObject primitive) {
    writeBytes(primitive.getInternalContent() ?? Uint8List(0));
  }

  void writeLiteral(PdfLiteral literal) {
    literal.setPosition(getCurrentPos());
    writeBytes(literal.getInternalContent() ?? Uint8List(0));
  }

  void writePdfName(PdfName name) {
    writeByte(47); // /
    writeBytes(name.getInternalContent() ?? Uint8List(0));
  }

  void writePdfNumber(PdfNumber number) {
    if (number.hasContent()) {
      writeBytes(number.getInternalContent() ?? Uint8List(0));
    } else {
      if (number.isDoubleNumber()) {
        writeDouble(number.doubleValue());
      } else {
        writeInteger(number.intValue());
      }
    }
  }

  void writePdfStringObject(PdfString pdfString) {
    // TODO: Encrypt if crypto is available
    if (pdfString.isHexWriting()) {
      writeByte(60); // <
      writeBytes(pdfString.getInternalContent() ?? Uint8List(0));
      writeByte(62); // >
    } else {
      writeByte(40); // (
      writeBytes(pdfString.getInternalContent() ?? Uint8List(0));
      writeByte(41); // )
    }
  }

  void writeIndirectReference(PdfIndirectReference ref) {
    if (ref.isFree()) {
      writePrimitive(PdfNull.pdfNull);
    } else {
      writeInteger(ref.getObjNumber());
      if (ref.getGenNumber() == 0) {
        writeString(" 0 R");
      } else {
        writeSpace();
        writeInteger(ref.getGenNumber());
        writeString(" R");
      }
    }
  }

  Future<void> _writeArray(PdfArray array) async {
    writeByte(91); // [
    for (var i = 0; i < array.size(); i++) {
      final value = await array.get(i, false);
      if (value != null) {
        final ref = value.getIndirectReference();
        if (ref != null) {
          writeIndirectReference(ref);
        } else {
          await writePdfObject(value);
        }
      } else {
        writePrimitive(PdfNull.pdfNull);
      }

      if (i < array.size() - 1) {
        writeSpace();
      }
    }
    writeByte(93); // ]
  }

  Future<void> _writeDictionary(PdfDictionary dict) async {
    writeBytes(_openDict);
    final keys = dict.keySet();
    for (final key in keys) {
      writePdfName(key);

      final value = await dict.get(key, false);
      if (value != null) {
        final type = value.getObjectType();
        if (type == PdfObjectType.number ||
            type == PdfObjectType.literal ||
            type == PdfObjectType.boolean ||
            type == PdfObjectType.nullType ||
            type == PdfObjectType.indirectReference ||
            value.checkState(PdfObject.mustBeIndirect)) {
          writeSpace();
        }

        final ref = value.getIndirectReference();
        if (ref != null) {
          writeIndirectReference(ref);
        } else {
          await writePdfObject(value);
        }
      } else {
        writeSpace();
        writePrimitive(PdfNull.pdfNull);
      }
    }
    writeBytes(_closeDict);
  }

  Future<void> _writePdfStream(PdfStream stream) async {
    await _writeDictionary(stream);
    writeBytes(_stream);
    final bytes = await stream.getBytes() ?? Uint8List(0);
    writeBytes(bytes);
    writeBytes(_endstream);
  }
}
