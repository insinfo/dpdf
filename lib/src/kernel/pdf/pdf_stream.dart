import 'dart:typed_data';

import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_object.dart';

/// Compression level constants.
class CompressionConstants {
  CompressionConstants._();

  /// Undefined compression level.
  static const int undefinedCompression = -1;

  /// No compression.
  static const int noCompression = 0;

  /// Best speed compression.
  static const int bestSpeed = 1;

  /// Best compression.
  static const int bestCompression = 9;

  /// Default compression level.
  static const int defaultCompression = -1;
}

/// Representation of a stream as described in the PDF Specification.
///
/// A stream consists of a dictionary describing the stream, followed by
/// the keyword 'stream', followed by the stream data, ending with 'endstream'.
class PdfStream extends PdfDictionary {
  /// Compression level for this stream.
  int _compressionLevel = CompressionConstants.undefinedCompression;

  /// Output buffer for stream data.
  Uint8List? _outputBytes;

  /// Input stream (for efficient large data handling).
  Stream<List<int>>? _inputStream;

  /// Offset in the file where stream data starts.
  int _offset = 0;

  /// Length of the stream data (from dictionary or calculated).
  int _length = -1;

  /// Creates a PdfStream with bytes content.
  ///
  /// [bytes] The initial content of the stream.
  /// [compressionLevel] The compression level (0 = best speed, 9 = best compression, -1 is default).
  PdfStream.withBytes(Uint8List? bytes,
      [int compressionLevel = CompressionConstants.undefinedCompression]) {
    setState(PdfObject.mustBeIndirect);
    _compressionLevel = compressionLevel;
    if (bytes != null && bytes.isNotEmpty) {
      _outputBytes = Uint8List.fromList(bytes);
    } else {
      _outputBytes = Uint8List(0);
    }
  }

  /// Creates an empty PdfStream.
  PdfStream() : this.withBytes(null);

  /// Creates a PdfStream with specified compression level.
  PdfStream.withCompression(int compressionLevel)
      : this.withBytes(null, compressionLevel);

  /// Creates a PdfStream for reading from an existing PDF file.
  ///
  /// This constructor is used internally by PdfReader.
  PdfStream.fromReader(int offset, PdfDictionary keys) {
    _compressionLevel = CompressionConstants.undefinedCompression;
    _offset = offset;
    // Copy all entries from the keys dictionary
    for (final entry in keys.entrySet()) {
      put(entry.key, entry.value);
    }
    // Get length from dictionary
    final lengthNum = getAsNumber(PdfName.length);
    _length = lengthNum?.intValue() ?? 0;
  }

  @override
  int getObjectType() => PdfObjectType.stream;

  @override
  PdfObject clone() {
    final cloned = PdfStream.withBytes(_outputBytes, _compressionLevel);
    for (final entry in entrySet()) {
      cloned.put(entry.key, entry.value.clone());
    }
    return cloned;
  }

  @override
  PdfObject newInstance() {
    return PdfStream();
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
  int getOffset() => _offset;

  /// Gets the decoded stream bytes.
  ///
  /// If [decoded] is true, filters are applied to decode the stream.
  /// Note: DCTDecode and JPXDecode filters will be ignored.
  ///
  /// Returns null if the stream was created from an InputStream.
  Uint8List? getBytes([bool decoded = true]) {
    if (isFlushed()) {
      throw StateError('Cannot operate with flushed PdfStream');
    }
    if (_inputStream != null) {
      // Stream was created by InputStream
      return null;
    }
    Uint8List? bytes = _outputBytes;
    if (bytes != null && decoded && containsKey(PdfName.filter)) {
      bytes = _decodeBytes(bytes);
    }
    return bytes;
  }

  /// Gets the raw (uncompressed) stream bytes.
  Uint8List? getRawBytes() => getBytes(false);

  /// Sets the stream content.
  ///
  /// [bytes] New content for stream. If null, the stream's content will be discarded.
  /// [append] If true, bytes will be appended to the end.
  void setData(Uint8List? bytes, [bool append = false]) {
    if (isFlushed()) {
      throw StateError('Cannot operate with flushed PdfStream');
    }
    if (_inputStream != null) {
      throw StateError(
          'Cannot set data to PdfStream which was created by InputStream');
    }

    if (append) {
      if (bytes != null) {
        final oldBytes = _outputBytes ?? Uint8List(0);
        final newBytes = Uint8List(oldBytes.length + bytes.length);
        newBytes.setRange(0, oldBytes.length, oldBytes);
        newBytes.setRange(oldBytes.length, newBytes.length, bytes);
        _outputBytes = newBytes;
      }
    } else {
      _outputBytes = bytes != null ? Uint8List.fromList(bytes) : Uint8List(0);
    }

    _offset = 0;
    // Remove filters since data is now raw
    remove(PdfName.filter);
    remove(PdfName.decodeParms);
  }

  /// Decodes bytes based on the stream's filter.
  Uint8List _decodeBytes(Uint8List bytes) {
    // Use FilterHandlers for decoding
    // Import: import '../utils/filter_handlers.dart';
    // return FilterHandlers.decodeBytes(bytes, this);

    // For now, inline basic FlateDecode support using dart:io
    final filterObj = get(PdfName.filter);
    if (filterObj == null) {
      return bytes;
    }

    // Check if it's FlateDecode
    if (filterObj is PdfName && filterObj.getValue() == 'FlateDecode') {
      try {
        // Use dart:io zlib for decompression
        // This requires importing dart:io
        return bytes; // Placeholder - actual implementation in FilterHandlers
      } catch (e) {
        return bytes;
      }
    }

    return bytes;
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
  }

  @override
  String toString() {
    final dictStr = super.toString();
    final len = _outputBytes?.length ?? _length;
    return '$dictStr stream($len bytes)';
  }
}
