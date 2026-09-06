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
  
  Sink<List<int>>? get sink => _sink;
  BytesBuilder? get builder => _builder;

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
  /// If [forceDirect] is true, writes object content directly (for ObjStm).
  Future<PdfOutputStream> writePdfObject(PdfObject pdfObject, {bool forceDirect = false}) async {
    // For ObjStm, we need to write the object content directly, not as a reference
    if (!forceDirect) {
      if (pdfObject.checkState(PdfObject.mustBeIndirect) && document != null) {
        pdfObject.makeIndirect(document!);
        pdfObject = pdfObject.getIndirectReference()!;
      }
    }

    switch (pdfObject.getObjectType()) {
      case PdfObjectType.array:
        await _writeArray(pdfObject as PdfArray);
        break;
      case PdfObjectType.dictionary:
        await _writeDictionary(pdfObject as PdfDictionary);
        break;
      case PdfObjectType.indirectReference:
        // For forceDirect, we should never reach here with the actual object
        // But if we do get a reference, resolve it and write directly
        if (forceDirect) {
          final resolved = await (pdfObject as PdfIndirectReference).getRefersTo();
          if (resolved != null) {
            await writePdfObject(resolved, forceDirect: true);
          }
        } else {
          writeIndirectReference(pdfObject as PdfIndirectReference);
        }
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
    var bytes = pdfString.getInternalContent() ?? Uint8List(0);

    if (crypto != null) {
      try {
        final isEmbeddedFilesOnly = (crypto as dynamic).isEmbeddedFilesOnly();
        if (!isEmbeddedFilesOnly) {
          bytes = (crypto as dynamic).encryptByteArray(bytes);
        }
      } catch (e) {
        // Ignore if crypto doesn't support these methods (should match PdfEncryption)
      }
    }

    if (pdfString.isHexWriting()) {
      writeByte(60); // <
      writeBytes(bytes);
      writeByte(62); // >
    } else {
      writeByte(40); // (
      // We might need to escape bytes if they are encrypted?
      // Encrypted bytes are arbitrary binary.
      // If we write arbitrary binary in (...) string, we must escape special chars like ), (, \.
      // But usually encrypted strings are written as HEX (<...>) to avoid escaping issues.
      // However, if the original string was not hex,  might force hex if encrypted?
      // Let's check  behavior.

      // Default to hex if encrypted to be safe, or just write bytes.
      // If we use (), we MUST escape.
      // PdfString usually handles escaping in generateContent/getInternalContent?
      // But getInternalContent here returns RAW or ESCAPED?
      // PdfString.getInternalContent() usually returns the bytes that go ON WIRE (escaped).
      // If we encrypt, we encrypt the RAW bytes.
      // Then we need to re-escape or switch to Hex.

      // Simplification: If encrypted, use Hex.
      if (crypto != null) {
        // Encrypted bytes -> always write as Hex for safety
        writeByte(60); // <
        for (var b in bytes) {
          // We need to write hex representation of bytes
          // This requires ByteUtils.getIsoBytesFromHexString or similar manually.
          final hex = b.toRadixString(16).padLeft(2, '0').toUpperCase();
          writeBytes(hex.codeUnits);
        }
        writeByte(62); // >
        return;
      }

      writeBytes(bytes);
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
        // Check if value should be written as reference (has indirect ref)
        final ref = value.getIndirectReference();
        
        final type = value.getObjectType();
        // Need space before: numbers, literals, booleans, null, refs, or anything with indirect ref
        if (type == PdfObjectType.number ||
            type == PdfObjectType.literal ||
            type == PdfObjectType.boolean ||
            type == PdfObjectType.nullType ||
            type == PdfObjectType.indirectReference ||
            ref != null ||
            value.checkState(PdfObject.mustBeIndirect)) {
          writeSpace();
        }

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
    final bytes = await stream.getBytes() ?? Uint8List(0);
    stream.put(PdfName.length, PdfNumber.fromInt(bytes.length));
    
    await _writeDictionary(stream);
    writeNewLine(); // Ensure separation
    writeBytes(_stream);
    writeBytes(bytes);
    writeBytes(_endstream);
  }
}
