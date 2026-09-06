import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import '../../io/source/byte_utils.dart';
import 'pdf_object.dart';
import 'pdf_array.dart';
import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_string.dart';
import 'pdf_literal.dart';
import 'pdf_boolean.dart';
import 'pdf_stream.dart';
import 'pdf_object_stream.dart'; // Added
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
  
  PdfObjectStream? _currentObjStream;

  PdfObjectStream? get currentObjStream => _currentObjStream;
  
  PdfWriter(this._output, {WriterProperties? properties, int initialPosition = 0})
      : properties = properties ?? WriterProperties(),
        _currentPos = initialPosition;

  factory PdfWriter.toFile(String path, {WriterProperties? properties}) {
    return PdfWriter(File(path).openWrite(), properties: properties);
  }

  /// Creates a PdfWriter that writes to a BytesBuilder.
  factory PdfWriter.fromBytesBuilder(BytesBuilder builder,
      {WriterProperties? properties}) {
    return PdfWriter(_BytesBuilderSink(builder), properties: properties);
  }

  int getPosition() => _currentPos;

  IOSink getSink() => _output;

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

  Future<void> writeObject(PdfObject obj, {bool canBeInObjStm = true}) async {
    final ref = obj.getIndirectReference();
    if (ref == null) return;

    // Object Stream Handling (Full Compression)
    if (properties.isFullCompression == true && canBeInObjStm && _canBeInObjStm(obj)) {
       if (_currentObjStream == null) {
         if (document == null) {
            throw StateError("Document must be set to use full compression");
         }
         _currentObjStream = PdfObjectStream(document!);
       }
       
       await _currentObjStream!.addObject(obj);
       
       // Mark as flushed in context of specific stream?
       // No, we mark it when we flush the ObjStm?
       // Actually, checkState(flushed) is used to prevent re-writing.
       // Here we set it to flushed because it IS written to the ObjStm.
       ref.setState(PdfObject.flushed);
       
       if (_currentObjStream!.getSize() >= PdfObjectStream.maxObjStreamSize) {
         await _flushObjectStream(_currentObjStream!);
         _currentObjStream = null;
       }
       return;
    }

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
    ref.setState(PdfObject.flushed);
    _isEncrypting = false; // Reset
  }
  
  bool _canBeInObjStm(PdfObject obj) {
     if (document == null) return false;
     // Helper logic: Streams, Encryption Dict, Catalog, etc cannot be in ObjStm sometimes?
     // Streams cannot be in ObjStm.
     if (obj.isStream()) return false;
     
     // Indirect references are allowed? No, references pointing to objects.
     // The object itself being written.
     // Encryption dictionary cannot be compressed usually (it's needed to read).
     if (obj == document?.getEncryption()?.getPdfObject()) return false;
     
     // Length of this writer's current stream?
     return true;
  }
  
  Future<void> _flushObjectStream(PdfObjectStream objStm) async {
     // Prepare stream data: Index + Objects
     // Index is in _indexStream (BytesBuilder)
     // Objects are in outputStream (BytesBuilder) via PdfStream mechanism
     
     // We need to merge them.
     // PdfObjectStream stores index in _indexStream.
     // And object data in the PdfStream's internal stream.
     
     final indexBytes = objStm.getIndexStream().builder!.toBytes();
     final objBytes = (await objStm.getBytes()) ?? Uint8List(0);
     
     final combined = BytesBuilder();
     combined.add(indexBytes);
     combined.add(objBytes);
     
     objStm.setData(combined.toBytes());
     
     await writeObject(objStm);
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

  // Handle indirect references BEFORE setting offset - we don't want to
  // overwrite the reference's offset when writing it as "N 0 R"
  if (obj.getObjectType() == PdfObjectType.indirectReference) {
    final refObj = obj as PdfIndirectReference;
    writeInt(refObj.getObjNumber());
    writeSpace();
    writeInt(refObj.getGenNumber());
    writeSpace();
    writeByte(0x52); // 'R'
    return;
  }

  obj.setOffset(getPosition());

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
      // Already handled above, but keep case for completeness
      break;
    case PdfObjectType.literal:
      _writeLiteral(obj as PdfLiteral);
      break;
  }
}

  void _writeLiteral(PdfLiteral literal) {
    final bytes = literal.getInternalContent();
    if (bytes != null) {
      writeBytes(bytes);
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
    
    stream.put(PdfName.length, PdfNumber.fromInt(bytes.length));

    await _writeDictionary(stream);
    writeNewLine();
    writeString('stream\n');
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
        // PDF spec: exactly 20 bytes per entry: 10 + 1 + 5 + 1 + 1 + 2 = 20
        // Format: nnnnnnnnnn ggggg f \r\n (CR+LF) or n \n (SP+LF)
        writeString('0000000000 65535 f \n');
      } else {
        final offset = ref.getOffset().toString().padLeft(10, '0');
        final gen = ref.getGenNumber().toString().padLeft(5, '0');
        final type = ref.isFree() ? 'f' : 'n';
        // Exactly 20 bytes: offset(10) + sp(1) + gen(5) + sp(1) + type(1) + sp(1) + LF(1)
        writeString('$offset $gen $type \n');
      }
    }
  }

  /// Writes an incremental xref table with only the modified entries.
  /// Used in append mode for signatures.
  void writeIncrementalXrefTable(
      PdfXrefTable xref, List<PdfIndirectReference> modifiedRefs) {
    writeString('xref\n');

    // Group modified refs by contiguous object numbers for efficient xref subsections
    if (modifiedRefs.isEmpty) {
      // Write empty xref
      writeString('0 0\n');
      return;
    }

    // Sort by object number
    modifiedRefs.sort((a, b) => a.getObjNumber().compareTo(b.getObjNumber()));

    // Write subsections for contiguous ranges
    int i = 0;
    while (i < modifiedRefs.length) {
      int start = modifiedRefs[i].getObjNumber();
      int end = start;

      // Find contiguous range
      while (i + 1 < modifiedRefs.length &&
          modifiedRefs[i + 1].getObjNumber() == end + 1) {
        i++;
        end = modifiedRefs[i].getObjNumber();
      }

      int count = end - start + 1;
      writeString('$start $count\n');

      // Write entries for this subsection
      for (int objNum = start; objNum <= end; objNum++) {
        final ref = xref.get(objNum);
        if (ref == null) {
          // PDF spec: exactly 20 bytes per entry
          writeString('0000000000 65535 f \n');
        } else {
          final offset = ref.getOffset().toString().padLeft(10, '0');
          final gen = ref.getGenNumber().toString().padLeft(5, '0');
          final type = ref.isFree() ? 'f' : 'n';
          // Exactly 20 bytes: offset(10) + sp(1) + gen(5) + sp(1) + type(1) + sp(1) + LF(1)
          writeString('$offset $gen $type \n');
        }
      }
      i++;
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

  Future<void> writeXrefStream(PdfXrefTable xref, PdfDictionary trailer, PdfStream xrefStream) async {
    xrefStream.put(PdfName.type, PdfName.xref);
    xrefStream.put(PdfName.size, PdfNumber.fromInt(xref.size()));

    // Copy entries from trailer to XRefStream using internal map to avoid async resolution
    final trailerMap = trailer.getMap();
    if (trailerMap != null) {
      for (final entry in trailerMap.entries) {
        if (entry.key != PdfName.size && entry.key != PdfName.type) {
           xrefStream.put(entry.key, entry.value);
        }
      }
    }

    // Determine field widths (W)
    int maxOffset = 0;
    int maxIndex = 0;
    
    // We need to iterate to find max values for W calculation
    // And also to build data.
    // Ideally we do one pass if possible, or two.
    // Let's iterate to find max.
    for (int i = 0; i < xref.size(); i++) {
        final ref = xref.get(i);
        if (ref != null) {
            if (ref.getObjStreamNumber() > 0) {
                 // Compressed: type 2
                 if (ref.getObjStreamNumber() > maxOffset) maxOffset = ref.getObjStreamNumber();
                 if (ref.getIndex() > maxIndex) maxIndex = ref.getIndex();
            } else {
                 if (ref.isFree()) {
                     // Free: type 0
                     // Field 2: next free - usually small or offset?
                     // Field 2: object number of next free object.
                     // But here we might just use offset logic.
                     // The standard says: type 0, field 2 = obj number of next free object.
                 } else {
                     // In-use: type 1
                     if (ref.getOffset() > maxOffset) maxOffset = ref.getOffset();
                     if (ref.getGenNumber() > maxIndex) maxIndex = ref.getGenNumber();
                 }
            }
        }
    }
    
    // Calculate bytes needed
    final w1 = 1; // Type always 1 byte (0,1,2)
    var w2 = 4;
    // Helper to calc bytes for integer
    if (maxOffset < 65536) w2 = 2;
    // else if (maxOffset < 4294967296) w2 = 4; // Dart ints are 64-bit, but offsets fit in 32? PDF allows big files.
    else if (maxOffset > 4294967295) w2 = 8;
    
    var w3 = 2;
    if (maxIndex < 65536) w3 = 2;
    else w3 = 4;

    xrefStream.put(PdfName.w, PdfArray.fromList([
        PdfNumber.fromInt(w1),
        PdfNumber.fromInt(w2),
        PdfNumber.fromInt(w3)
    ]));

    // Generate data
    final builder = BytesBuilder();
    
    // Build index array if needed (for subsections)
    // For now assuming contiguous 0..size.
    // Or we should support subsections using /Index [first size first size ...]
    // Standard recommended subsections for sparse tables.
    // For now simplistic assumption: 0..N
    // TODO: Optimize with /Index for sparse tables
    
    for (int i = 0; i < xref.size(); i++) {
        final ref = xref.get(i);
        
        int type = 0;
        int field2 = 0;
        int field3 = 0;
        
        if (ref == null) {
             // Implicitly free or missing?
             // Treat as free, offset 0?
             type = 0;
             field2 = 0; // Next free?
             field3 = 65535;
        } else if (ref.isFree()) {
             type = 0;
             // Field 2 is next free obj number.
             // We don't track next free chain in simple implementation easily without traversing.
             // But if we just mark it free, does it matter?
             // A conforming reader might ignore.
             field2 = 0; 
             field3 = 65535;
        } else if (ref.getObjStreamNumber() > 0) {
             type = 2;
             field2 = ref.getObjStreamNumber();
             field3 = ref.getIndex();
        } else {
             type = 1;
             field2 = ref.getOffset();
             field3 = ref.getGenNumber();
        }
        
        // Write W1
        builder.addByte(type);
        
        // Write W2
        _writeBytesBigEndian(builder, field2, w2);
        
        // Write W3
        _writeBytesBigEndian(builder, field3, w3);
    }
    
    xrefStream.setData(builder.toBytes());
    
    // Write XRefStream object
    // It must be indirect.
    // If it doesn't have a ref, make it?
    // It's usually the current size if not assigned.
    // But normally createNextIndirectRef assigned one.
    // We allocate a number for it.
    
    // Typically PdfDocument handles allocation.
    // We assume it is passed or we create one?
    // Let's create a dummy ref if missing, but it should be passed or assigned.
    // In writeObject, if no ref, returns.
    
    // Assuming PdfDocument creates the object for XRefStream and puts it in xref table?
    // But XRefStream doesn't go INTO xref table usually (it's implicit).
    // Wait, ISO 32000: "The cross-reference stream object... shall be indirect"
    
    // Let's just create a temp ref if needed, but it should be part of the flow.
    // We will call writeObject(xrefStream).
    
    await writeObject(xrefStream);
  }

  void _writeBytesBigEndian(BytesBuilder builder, int value, int length) {
      for (int i = length - 1; i >= 0; i--) {
          builder.addByte((value >> (8 * i)) & 0xFF);
      }
  }

  Future<void> flush() async {
      // Should we flush current ObjStm?
      // flush() is synchronous. writeObject is async.
      // We might need an async flush method or call it closes.
  }
  
  Future<void> flushAsync() async {
      if (_currentObjStream != null) {
          await _flushObjectStream(_currentObjStream!);
          _currentObjStream = null;
      }
  }

  Future<void> close() async {
    await flushAsync();
    await _output.close();
  }
}

class _BytesBuilderSink implements IOSink {
  final BytesBuilder builder;
  final Completer<void> _completer = Completer<void>();

  _BytesBuilderSink(this.builder);

  @override
  void add(List<int> data) {
    builder.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _completer.completeError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      builder.add(data);
    }
  }

  @override
  Future<void> close() async {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  @override
  Future<void> get done => _completer.future;

  @override
  void write(Object? object) {
    add(ByteUtils.getIsoBytes(object.toString()));
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    for (final obj in objects) {
      if (!first) write(separator);
      write(obj);
      first = false;
    }
  }

  @override
  void writeCharCode(int charCode) {
    add([charCode]);
  }

  @override
  void writeln([Object? object = '']) {
    write(object);
    write('\n');
  }

  @override
  set encoding(_) => throw UnimplementedError();
  @override
  get encoding => throw UnimplementedError();

  @override
  Future<void> flush() async {}
}
