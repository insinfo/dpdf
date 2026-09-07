import 'dart:typed_data';

import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'compression_constants.dart';
import 'pdf_object.dart';
import 'pdf_output_stream.dart';
import '../utils/filter_handlers.dart';

/// PDF stream dictionary and payload representation.
///
/// A stream consists of a dictionary describing the stream, followed by
/// the keyword 'stream', followed by the stream data, ending with 'endstream'.
class CraftPdfStream extends CraftPdfDictionary {
  /// Compression level for this stream.
  int _compressionLevel = CraftCompressionConstants.undefinedCompression;

  /// Output buffer for stream data.
  Uint8List? _outputBytes;

  /// Input stream (for efficient large data handling).
  Stream<List<int>>? _inputStream;

  /// Offset in the file where stream data starts.
  int _offset = 0;

  /// Length of the stream data (from dictionary or calculated).
  int _length = -1;

  CraftPdfOutputStream? _outputStream;
  BytesBuilder? _bytesBuilder;

  /// Creates a PdfStream with bytes content.
  ///
  /// [bytes] The initial content of the stream.
  /// [compressionLevel] The compression level (0 = best speed, 9 = best compression, -1 is default).
  CraftPdfStream.withBytes(Uint8List? bytes,
      [int compressionLevel = CraftCompressionConstants.undefinedCompression]) {
    setState(CraftPdfObject.mustBeIndirect);
    _compressionLevel = compressionLevel;
    if (bytes != null && bytes.isNotEmpty) {
      _outputBytes = Uint8List.fromList(bytes);
    }
  }

  /// Creates an empty PdfStream.
  CraftPdfStream() : this.withBytes(null);

  /// Creates a PdfStream with specified compression level.
  CraftPdfStream.withCompression(int compressionLevel)
      : this.withBytes(null, compressionLevel);

  /// Creates a PdfStream for reading from an existing PDF file.
  static Future<CraftPdfStream> fromReader(
      int offset, CraftPdfDictionary keys) async {
    final stream = CraftPdfStream();
    stream._compressionLevel = CraftCompressionConstants.undefinedCompression;
    stream._offset = offset;
    // Copy all entries from the keys dictionary
    final entries = await keys.entrySet();
    for (final entry in entries) {
      stream.put(entry.key, entry.value);
    }
    // Get length from dictionary
    final lengthNum = await stream.numberEntry(CraftPdfName.length);
    stream._length = lengthNum?.intValue() ?? 0;
    return stream;
  }

  @override
  int objectKind() => PdfObjectType.stream;

  @override
  CraftPdfObject clone() {
    Uint8List? bytes;
    if (_bytesBuilder != null) {
      bytes = _bytesBuilder!.toBytes();
    } else {
      bytes = _outputBytes;
    }

    final cloned = CraftPdfStream.withBytes(bytes, _compressionLevel);
    // Note: Clone here is sync
    final map = getMap();
    if (map != null) {
      for (final entry in map.entries) {
        cloned.put(entry.key, entry.value.clone());
      }
    }
    return cloned;
  }

  @override
  CraftPdfObject newInstance() {
    return CraftPdfStream();
  }

  /// Gets the compression level of this stream.
  int getCompressionLevel() => _compressionLevel;

  /// Sets the compression level.
  ///
  /// [compressionLevel] 0 = best speed, 9 = best compression, -1 is default.
  void setCompressionLevel(int compressionLevel) {
    _compressionLevel = compressionLevel;
  }

  /// Gets the stream data length.
  int getLength() => _length;

  /// Gets the offset where stream data starts in the file.
  @override
  int getOffset() => _offset;

  /// Gets the output stream.
  CraftPdfOutputStream getOutputStream() {
    if (_outputStream == null) {
      _bytesBuilder = BytesBuilder();
      if (_outputBytes != null) {
        _bytesBuilder!.add(_outputBytes!);
        // _outputBytes = null; // Keep it as fallback or clear? safer to clear to avoid dupe
      }
      _outputStream = CraftPdfOutputStream.fromBuilder(_bytesBuilder!);
    }
    return _outputStream!;
  }

  /// Gets the decoded stream bytes.
  ///
  /// If [decoded] is true, filters are applied to decode the stream.
  /// Note: DCTDecode and JPXDecode filters will be ignored.
  ///
  /// Returns null if the stream was created from an InputStream.
  Future<Uint8List?> getBytes([bool decoded = true]) async {
    if (hasBeenWritten()) {
      throw StateError('Cannot operate with flushed PdfStream');
    }
    if (_inputStream != null) {
      // Stream was created by InputStream
      return null;
    }

    Uint8List? bytes;
    if (_bytesBuilder != null) {
      bytes = _bytesBuilder!.toBytes();
    } else {
      bytes = _outputBytes;
    }

    if (bytes != null && decoded && containsKey(CraftPdfName.filter)) {
      bytes = await CraftFilterHandlers.decodeBytes(bytes, this);
    }
    return bytes;
  }

  /// Gets the raw (uncompressed) stream bytes.
  Future<Uint8List?> getRawBytes() async => await getBytes(false);

  /// Sets the stream content.
  ///
  /// [bytes] New content for stream. If null, the stream's content will be discarded.
  /// [append] If true, bytes will be appended to the end.
  void setData(Uint8List? bytes, [bool append = false]) {
    if (hasBeenWritten()) {
      throw StateError('Cannot operate with flushed PdfStream');
    }
    if (_inputStream != null) {
      throw StateError(
          'Cannot set data to PdfStream which was created by InputStream');
    }

    if (append) {
      if (bytes != null) {
        getOutputStream().writeBytes(bytes);
      }
    } else {
      // Replace content
      _bytesBuilder = BytesBuilder();
      _outputStream = CraftPdfOutputStream.fromBuilder(_bytesBuilder!);
      _outputBytes = null;
      if (bytes != null) {
        _bytesBuilder!.add(bytes);
      }
    }

    _offset = 0;
    // Remove filters since data is now raw
    remove(CraftPdfName.filter);
    remove(CraftPdfName.decodeParms);
  }

  /// Updates the length field.
  void updateLength(int length) {
    _length = length;
  }

  /// Releases the stream content.
  @override
  void releaseContent() {
    super.releaseContent();
    _outputBytes = null;
    _inputStream = null;
    _bytesBuilder = null;
    _outputStream = null;
  }

  @override
  String toString() {
    final dictStr = super.toString();
    var len = _length;
    if (_bytesBuilder != null) {
      len = _bytesBuilder!.length;
    } else if (_outputBytes != null) {
      len = _outputBytes!.length;
    }
    return '$dictStr stream($len bytes)';
  }
}
