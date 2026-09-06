import 'dart:io';
import 'dart:typed_data';

/// Writes PNG images.
///
/// Provides methods to create valid PNG files with proper chunk structure,
/// CRC32 checksums, and optional palette/ICC profile support.
class PngWriter {
  static final Uint8List _pngSignature =
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

  static final Uint8List _ihdr =
      Uint8List.fromList([0x49, 0x48, 0x44, 0x52]); // IHDR
  static final Uint8List _plte =
      Uint8List.fromList([0x50, 0x4C, 0x54, 0x45]); // PLTE
  static final Uint8List _idat =
      Uint8List.fromList([0x49, 0x44, 0x41, 0x54]); // IDAT
  static final Uint8List _iend =
      Uint8List.fromList([0x49, 0x45, 0x4E, 0x44]); // IEND
  static final Uint8List _iccp =
      Uint8List.fromList([0x69, 0x43, 0x43, 0x50]); // iCCP

  static Int32List? _crcTable;

  final BytesBuilder _output = BytesBuilder();

  /// Creates a PngWriter with PNG signature.
  PngWriter() {
    _output.add(_pngSignature);
  }

  /// Writes the IHDR chunk with image dimensions and format.
  ///
  /// [width] - Image width
  /// [height] - Image height
  /// [bitDepth] - Bits per sample (1, 2, 4, 8, or 16)
  /// [colorType] - Color type (0=grayscale, 2=RGB, 3=indexed, 4=grayscale+alpha, 6=RGBA)
  void writeHeader(int width, int height, int bitDepth, int colorType) {
    final ms = BytesBuilder();
    _outputIntToBuilder(width, ms);
    _outputIntToBuilder(height, ms);
    ms.addByte(bitDepth);
    ms.addByte(colorType);
    ms.addByte(0); // compression method
    ms.addByte(0); // filter method
    ms.addByte(0); // interlace method
    writeChunk(_ihdr, ms.toBytes());
  }

  /// Writes the IEND chunk to finalize the image.
  void writeEnd() {
    writeChunk(_iend, Uint8List(0));
  }

  /// Writes image data as IDAT chunk with zlib compression.
  ///
  /// [data] - Raw pixel data
  /// [stride] - Bytes per row
  void writeData(Uint8List data, int stride) {
    final uncompressed = BytesBuilder();

    int k;
    for (k = 0; k < data.length - stride; k += stride) {
      uncompressed.addByte(0); // filter type: none
      uncompressed.add(data.sublist(k, k + stride));
    }

    int remaining = data.length - k;
    if (remaining > 0) {
      uncompressed.addByte(0);
      uncompressed.add(data.sublist(k, k + remaining));
    }

    final compressed = zlib.encode(uncompressed.toBytes());
    writeChunk(_idat, Uint8List.fromList(compressed));
  }

  /// Writes a palette (PLTE) chunk.
  void writePalette(Uint8List data) {
    writeChunk(_plte, data);
  }

  /// Writes an ICC profile (iCCP) chunk.
  void writeIccProfile(Uint8List data) {
    final stream = BytesBuilder();
    stream.addByte(0x49); // 'I'
    stream.addByte(0x43); // 'C'
    stream.addByte(0x43); // 'C'
    stream.addByte(0); // null terminator
    stream.addByte(0); // compression method

    final compressed = zlib.encode(data);
    stream.add(compressed);

    writeChunk(_iccp, stream.toBytes());
  }

  /// Initializes the CRC table.
  static void _makeCrcTable() {
    if (_crcTable != null) return;

    final crc2 = Int32List(256);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int k = 0; k < 8; k++) {
        if ((c & 1) != 0) {
          c = 0xedb88320 ^ (c >>> 1);
        } else {
          c = c >>> 1;
        }
      }
      crc2[n] = c;
    }
    _crcTable = crc2;
  }

  /// Updates CRC with data.
  static int _updateCrc(int crc, Uint8List buf, int offset, int len) {
    int c = crc;
    if (_crcTable == null) _makeCrcTable();

    for (int n = 0; n < len; n++) {
      c = _crcTable![(c ^ buf[offset + n]) & 0xff] ^ (c >>> 8);
    }
    return c;
  }

  /// Outputs a 32-bit integer in big-endian format.
  void outputInt(int n) {
    _output.addByte((n >> 24) & 0xFF);
    _output.addByte((n >> 16) & 0xFF);
    _output.addByte((n >> 8) & 0xFF);
    _output.addByte(n & 0xFF);
  }

  /// Outputs an int to a BytesBuilder.
  static void _outputIntToBuilder(int n, BytesBuilder s) {
    s.addByte((n >> 24) & 0xFF);
    s.addByte((n >> 16) & 0xFF);
    s.addByte((n >> 8) & 0xFF);
    s.addByte(n & 0xFF);
  }

  /// Writes a PNG chunk with proper length and CRC.
  void writeChunk(Uint8List chunkType, Uint8List data) {
    outputInt(data.length);
    _output.add(chunkType);
    _output.add(data);

    int c = _updateCrc(-1, chunkType, 0, chunkType.length);
    c = ~_updateCrc(c, data, 0, data.length);
    outputInt(c);
  }

  /// Gets the final PNG data.
  Uint8List toBytes() => _output.toBytes();
}
