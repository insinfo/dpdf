import 'dart:typed_data';

import 'package:pdfcraft/src/io/source/byte_utils.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_array.dart';

import 'package:pdfcraft/src/kernel/pdf/pdf_dictionary.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_literal.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_name.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_null.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_number.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_object.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_primitive_object.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_stream.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_string.dart';

/// PdfOutputStream class represents an algorithm for writing data into content stream.
class CraftPdfOutputStream {
  final Sink<List<int>>? _sink;
  final BytesBuilder? _builder;
  int _currentPos = 0;

  /// Document associated with PdfOutputStream.
  CraftPdfDocument? document;

  // Crypto field for compatibility/future use
  // PdfEncryption? crypto; // Uncomment if imported
  dynamic crypto; // Placeholder to resolve TODO without adding deps loop

  // Cache standard bytes
  static final Uint8List _space = Uint8List.fromList([32]);
  static final Uint8List _newline = Uint8List.fromList([10]);
  static final Uint8List _openDict = Uint8List.fromList([60, 60]); // <<
  static final Uint8List _closeDict = Uint8List.fromList([62, 62]); // >>
  static final Uint8List _stream = CraftByteUtils.getIsoBytes("stream\n");
  static final Uint8List _endstream = CraftByteUtils.getIsoBytes("\nendstream");

  CraftPdfOutputStream(Sink<List<int>> sink)
      : _sink = sink,
        _builder = null;

  Sink<List<int>>? get sink => _sink;
  BytesBuilder? get builder => _builder;

  CraftPdfOutputStream.fromBuilder(BytesBuilder builder)
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
    writeBytes(CraftByteUtils.getIsoBytes(s));
  }

  /// Writes an integer.
  CraftPdfOutputStream writeInteger(int n) {
    writeBytes(CraftByteUtils.getIsoBytesFromInt(n));
    return this;
  }

  /// Writes a long (represented as int in Dart).
  CraftPdfOutputStream writeLong(int n) {
    writeString(n.toString());
    return this;
  }

  /// Writes a double.
  CraftPdfOutputStream writeDouble(double d) {
    writeBytes(CraftByteUtils.getIsoBytesFromDouble(d));
    return this;
  }

  /// Writes a float (same as double in Dart).
  CraftPdfOutputStream writeFloat(double f) {
    writeDouble(f);
    return this;
  }

  /// Writes a space character.
  CraftPdfOutputStream writeSpace() {
    writeBytes(_space);
    return this;
  }

  /// Writes a newline character.
  void writeNewLine() {
    writeBytes(_newline);
  }

  /// Write a PdfObject to the outputstream.
  /// If [forceDirect] is true, writes object content directly (for ObjStm).
  Future<CraftPdfOutputStream> writePdfObject(CraftPdfObject pdfObject,
      {bool forceDirect = false}) async {
    // For ObjStm, we need to write the object content directly, not as a reference
    if (!forceDirect) {
      if (pdfObject.checkState(CraftPdfObject.mustBeIndirect) &&
          document != null) {
        pdfObject.attachToDocument(document!);
        pdfObject = pdfObject.indirectHandle()!;
      }
    }

    switch (pdfObject.objectKind()) {
      case PdfObjectType.array:
        await _writeArray(pdfObject as CraftPdfArray);
        break;
      case PdfObjectType.dictionary:
        await _writeDictionary(pdfObject as CraftPdfDictionary);
        break;
      case PdfObjectType.indirectReference:
        // For forceDirect, we should never reach here with the actual object
        // But if we do get a reference, resolve it and write directly
        if (forceDirect) {
          final resolved =
              await (pdfObject as CraftPdfIndirectReference).targetObject();
          if (resolved != null) {
            await writePdfObject(resolved, forceDirect: true);
          }
        } else {
          writeIndirectReference(pdfObject as CraftPdfIndirectReference);
        }
        break;
      case PdfObjectType.name:
        writePdfName(pdfObject as CraftPdfName);
        break;
      case PdfObjectType.nullType:
      case PdfObjectType.boolean:
        writePrimitive(pdfObject as CraftPdfPrimitiveObject);
        break;
      case PdfObjectType.literal:
        writeLiteral(pdfObject as CraftPdfLiteral);
        break;
      case PdfObjectType.string:
        writePdfStringObject(pdfObject as CraftPdfString);
        break;
      case PdfObjectType.number:
        writePdfNumber(pdfObject as CraftPdfNumber);
        break;
      case PdfObjectType.stream:
        await _writePdfStream(pdfObject as CraftPdfStream);
        break;
    }
    return this;
  }

  void writePrimitive(CraftPdfPrimitiveObject primitive) {
    writeBytes(primitive.getInternalContent() ?? Uint8List(0));
  }

  void writeLiteral(CraftPdfLiteral literal) {
    literal.setPosition(getCurrentPos());
    writeBytes(literal.getInternalContent() ?? Uint8List(0));
  }

  void writePdfName(CraftPdfName name) {
    writeByte(47); // /
    writeBytes(name.getInternalContent() ?? Uint8List(0));
  }

  void writePdfNumber(CraftPdfNumber number) {
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

  void writePdfStringObject(CraftPdfString pdfString) {
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

  void writeIndirectReference(CraftPdfIndirectReference ref) {
    if (ref.isFree()) {
      writePrimitive(CraftPdfNull.pdfNull);
    } else {
      writeInteger(ref.objectNumber());
      if (ref.generationNumber() == 0) {
        writeString(" 0 R");
      } else {
        writeSpace();
        writeInteger(ref.generationNumber());
        writeString(" R");
      }
    }
  }

  Future<void> _writeArray(CraftPdfArray array) async {
    writeByte(91); // [
    for (var i = 0; i < array.size(); i++) {
      final value = await array.get(i, false);
      if (value != null) {
        final ref = value.indirectHandle();
        if (ref != null) {
          writeIndirectReference(ref);
        } else {
          await writePdfObject(value);
        }
      } else {
        writePrimitive(CraftPdfNull.pdfNull);
      }

      if (i < array.size() - 1) {
        writeSpace();
      }
    }
    writeByte(93); // ]
  }

  Future<void> _writeDictionary(CraftPdfDictionary dict) async {
    writeBytes(_openDict);
    final keys = dict.keySet();
    for (final key in keys) {
      writePdfName(key);

      final value = await dict.get(key, false);
      if (value != null) {
        // Check if value should be written as reference (has indirect ref)
        final ref = value.indirectHandle();

        final type = value.objectKind();
        // Need space before: numbers, literals, booleans, null, refs, or anything with indirect ref
        if (type == PdfObjectType.number ||
            type == PdfObjectType.literal ||
            type == PdfObjectType.boolean ||
            type == PdfObjectType.nullType ||
            type == PdfObjectType.indirectReference ||
            ref != null ||
            value.checkState(CraftPdfObject.mustBeIndirect)) {
          writeSpace();
        }

        if (ref != null) {
          writeIndirectReference(ref);
        } else {
          await writePdfObject(value);
        }
      } else {
        writeSpace();
        writePrimitive(CraftPdfNull.pdfNull);
      }
    }
    writeBytes(_closeDict);
  }

  Future<void> _writePdfStream(CraftPdfStream stream) async {
    final bytes = await stream.getBytes() ?? Uint8List(0);
    stream.put(CraftPdfName.length, CraftPdfNumber.fromInt(bytes.length));

    await _writeDictionary(stream);
    writeNewLine(); // Ensure separation
    writeBytes(_stream);
    writeBytes(bytes);
    writeBytes(_endstream);
  }
}
