import 'dart:io';
import 'dart:typed_data';

import '../../io/source/byte_utils.dart';
import 'pdf_object.dart';
import 'pdf_array.dart';
import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_string.dart';
import 'pdf_boolean.dart';
import 'pdf_stream.dart';
import 'pdf_xref_table.dart';
import 'pdf_document.dart';
import 'writer_properties.dart';

/// Writes PDF documents to output.
class PdfWriter {
  static final Uint8List _obj = ByteUtils.getIsoBytes(' obj\n');
  static final Uint8List _endobj = ByteUtils.getIsoBytes('\nendobj\n');

  final IOSink _output;
  int _currentPos = 0;
  String _pdfVersion = '1.7';

  PdfDocument? document;
  final WriterProperties properties;
  bool _isEncrypting = false;

  PdfWriter._(this._output, {WriterProperties? properties})
      : properties = properties ?? WriterProperties();

  factory PdfWriter.toFile(String path, {WriterProperties? properties}) {
    return PdfWriter._(File(path).openWrite(), properties: properties);
  }

  int getPosition() => _currentPos;

  void writeBytes(Uint8List bytes) {
    _output.add(bytes);
    _currentPos += bytes.length;
  }

  void writeString(String str) {
    writeBytes(ByteUtils.getIsoBytes(str));
  }

  void writeByte(int byte) {
    writeBytes(Uint8List.fromList([byte]));
  }

  void writeInt(int value) {
    writeString(value.toString());
  }

  void writeSpace() {
    writeByte(0x20);
  }

  void writeNewLine() {
    writeByte(0x0A);
  }

  void writeHeader() {
    writeString('%PDF-$_pdfVersion\n');
    writeBytes(Uint8List.fromList([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]));
  }

  Future<void> writeObject(PdfObject obj) async {
    final ref = obj.getIndirectReference();
    if (ref == null) return;

    ref.setOffset(getPosition());
    writeInt(ref.getObjNumber());
    writeSpace();
    writeInt(ref.getGenNumber());
    writeBytes(_obj);

    // Encryption setup
    _isEncrypting = false;
    if (document?.getEncryption() != null) {
      final enc = document!.getEncryption()!;
      // Do not encrypt the Encryption Dictionary itself
      if (obj != enc.getPdfObject()) {
        enc.setHashKeyForNextObject(ref.getObjNumber(), ref.getGenNumber());
        _isEncrypting = true;
      }
    }

    await _writeValue(obj, forceDirect: true);
    writeBytes(_endobj);
    _isEncrypting = false; // Reset
  }

  Future<void> _writeValue(PdfObject obj, {bool forceDirect = false}) async {
    final ref = obj.getIndirectReference();
    if (ref != null && !forceDirect) {
      writeInt(ref.getObjNumber());
      writeSpace();
      writeInt(ref.getGenNumber());
      writeSpace();
      writeByte(0x52); // 'R'
      return;
    }

    switch (obj.getObjectType()) {
      case PdfObjectType.nullType:
        writeString('null');
        break;
      case PdfObjectType.boolean:
        writeString((obj as PdfBoolean).getValue() ? 'true' : 'false');
        break;
      case PdfObjectType.number:
        writeString((obj as PdfNumber).toString());
        break;
      case PdfObjectType.string:
        _writeString(obj as PdfString);
        break;
      case PdfObjectType.name:
        _writeName(obj as PdfName);
        break;
      case PdfObjectType.array:
        await _writeArray(obj as PdfArray);
        break;
      case PdfObjectType.dictionary:
        await _writeDictionary(obj as PdfDictionary);
        break;
      case PdfObjectType.stream:
        await _writeStream(obj as PdfStream);
        break;
      case PdfObjectType.indirectReference:
        final ref = obj as PdfIndirectReference;
        writeInt(ref.getObjNumber());
        writeSpace();
        writeInt(ref.getGenNumber());
        writeSpace();
        writeByte(0x52); // 'R'
        break;
    }
  }

  void _writeName(PdfName name) {
    writeString(name.toString());
  }

  void _writeString(PdfString str) {
    var bytes = str.getValueBytes() ?? Uint8List(0);

    if (_isEncrypting && document?.getEncryption() != null) {
      final enc = document!.getEncryption()!;
      if (!enc.isEmbeddedFilesOnly()) {
        // Basic check, ideally more complex
        final builder = BytesBuilder();
        final osEnc = enc.getEncryptionStream(builder);
        if (osEnc != null) {
          osEnc.write(bytes);
          osEnc.finish();
          bytes = builder.toBytes();
        }
      }
    }

    if (str.isHexWriting() || _isEncrypting) {
      // Encrypted strings usually hex safe
      writeByte(0x3C); // '<'
      for (final b in bytes) {
        writeString(b.toRadixString(16).padLeft(2, '0').toUpperCase());
      }
      writeByte(0x3E); // '>'
    } else {
      writeByte(0x28); // '('
      for (final b in bytes) {
        if (b == 0x28 || b == 0x29 || b == 0x5C) writeByte(0x5C);
        writeByte(b);
      }
      writeByte(0x29); // ')'
    }
  }

  Future<void> _writeArray(PdfArray arr) async {
    writeByte(0x5B); // '['
    for (var i = 0; i < arr.size(); i++) {
      if (i > 0) writeSpace();
      final val = await arr.get(i);
      if (val != null) {
        await _writeValue(val);
      } else {
        writeString('null');
      }
    }
    writeByte(0x5D); // ']'
  }

  Future<void> _writeDictionary(PdfDictionary dict) async {
    writeString('<<');
    for (final key in dict.keySet()) {
      _writeName(key);
      writeSpace();
      final value = await dict.get(key, false);
      if (value != null) {
        await _writeValue(value);
      } else {
        writeString('null');
      }
      writeSpace();
    }
    writeString('>>');
  }

  Future<void> _writeStream(PdfStream stream) async {
    await _writeDictionary(stream);
    writeNewLine();
    writeString('stream\n');
    var bytes = await stream.getBytes() ?? Uint8List(0);

    if (_isEncrypting && document?.getEncryption() != null) {
      final enc = document!.getEncryption()!;
      // Streams are usually encrypted unless Metadata?
      // Metadata stream? Need check. For now encrypt all streams in obj.
      final builder = BytesBuilder();
      final osEnc = enc.getEncryptionStream(builder);
      if (osEnc != null) {
        osEnc.write(bytes);
        osEnc.finish();
        bytes = builder.toBytes();
      }
    }

    writeBytes(bytes);
    writeNewLine();
    writeString('endstream');
  }

  void writeXrefTable(PdfXrefTable xref) {
    writeString('xref\n');
    writeString('0 ${xref.size()}\n');
    for (var i = 0; i < xref.size(); i++) {
      final ref = xref.get(i);
      if (ref == null) {
        writeString('0000000000 65535 f \r\n');
      } else {
        final offset = ref.getOffset().toString().padLeft(10, '0');
        final gen = ref.getGenNumber().toString().padLeft(5, '0');
        final type = ref.isFree() ? 'f' : 'n';
        writeString('$offset $gen $type \r\n');
      }
    }
  }

  Future<void> writeTrailer(PdfDictionary trailer, int startxref) async {
    writeString('trailer\n');
    await _writeValue(trailer);
    writeNewLine();
    writeString('startxref\n');
    writeInt(startxref);
    writeNewLine();
  }

  void writeEOF() {
    writeString('%%EOF\n');
  }

  void flush() {}

  Future<void> close() async {
    await _output.close();
  }
}
