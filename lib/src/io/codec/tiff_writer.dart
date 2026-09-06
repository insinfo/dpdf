import 'dart:typed_data';
import 'tiff_constants.dart';
import 'lzw_compressor.dart';

/// Exports images as TIFF.
class TiffWriter {
  final Map<int, FieldBase> _ifd = {};

  /// Adds a field to the IFD.
  void addField(FieldBase field) {
    _ifd[field.tag] = field;
  }

  /// Gets the size of the IFD.
  int getIfdSize() => 6 + _ifd.length * 12;

  /// Writes the TIFF file to the output.
  void writeFile(BytesBuilder output) {
    // Write header MM (big-endian)
    output.addByte(0x4d);
    output.addByte(0x4d);
    // Magic number 42
    output.addByte(0);
    output.addByte(42);
    // IFD offset
    _writeLong(8, output);

    // Write IFD entry count
    _writeShort(_ifd.length, output);

    // Calculate value offsets
    int offset = 8 + getIfdSize();
    final sortedKeys = _ifd.keys.toList()..sort();

    for (final key in sortedKeys) {
      final field = _ifd[key]!;
      final size = field.getValueSize();
      if (size > 4) {
        field.setOffset(offset);
        offset += size;
      }
      field.writeField(output);
    }

    // Write next IFD offset (0 = no more IFDs)
    _writeLong(0, output);

    // Write field values
    for (final key in sortedKeys) {
      _ifd[key]!.writeValue(output);
    }
  }

  /// Compresses data using LZW with optional horizontal differencing predictor.
  static void compressLzw(
    BytesBuilder output,
    int predictor,
    Uint8List data,
    int height,
    int samplesPerPixel,
    int stride,
  ) {
    final compressor = LZWCompressor(output, 8, true);
    final usePredictor =
        predictor == TiffConstants.predictorHorizontalDifferencing;

    if (!usePredictor) {
      compressor.compress(data, 0, data.length);
    } else {
      int off = 0;
      final rowBuf = Uint8List(stride);
      for (int i = 0; i < height; i++) {
        rowBuf.setRange(0, stride, data, off);
        for (int j = stride - 1; j >= samplesPerPixel; j--) {
          rowBuf[j] = (rowBuf[j] - rowBuf[j - samplesPerPixel]) & 0xFF;
        }
        compressor.compress(rowBuf, 0, stride);
        off += stride;
      }
    }
    compressor.flush();
  }

  static void _writeShort(int v, BytesBuilder output) {
    output.addByte((v >> 8) & 0xff);
    output.addByte(v & 0xff);
  }

  static void _writeLong(int v, BytesBuilder output) {
    output.addByte((v >> 24) & 0xff);
    output.addByte((v >> 16) & 0xff);
    output.addByte((v >> 8) & 0xff);
    output.addByte(v & 0xff);
  }
}

/// Base class for TIFF IFD fields.
abstract class FieldBase {
  final int tag;
  final int fieldType;
  final int count;
  late Uint8List data;
  int _offset = 0;

  FieldBase(this.tag, this.fieldType, this.count);

  /// Gets the size needed for the value.
  int getValueSize() => (data.length + 1) & 0xfffffffe;

  /// Sets the offset for values > 4 bytes.
  void setOffset(int offset) => _offset = offset;

  /// Writes the field entry.
  void writeField(BytesBuilder output) {
    TiffWriter._writeShort(tag, output);
    TiffWriter._writeShort(fieldType, output);
    TiffWriter._writeLong(count, output);

    if (data.length <= 4) {
      output.add(data);
      for (int k = data.length; k < 4; ++k) {
        output.addByte(0);
      }
    } else {
      TiffWriter._writeLong(_offset, output);
    }
  }

  /// Writes the field value if > 4 bytes.
  void writeValue(BytesBuilder output) {
    if (data.length <= 4) return;
    output.add(data);
    if ((data.length & 1) == 1) {
      output.addByte(0);
    }
  }
}

/// Short field (16-bit).
class FieldShort extends FieldBase {
  FieldShort(int tag, int value) : super(tag, 3, 1) {
    data = Uint8List(2);
    data[0] = (value >> 8) & 0xFF;
    data[1] = value & 0xFF;
  }

  FieldShort.fromList(int tag, List<int> values)
      : super(tag, 3, values.length) {
    data = Uint8List(values.length * 2);
    int ptr = 0;
    for (final value in values) {
      data[ptr++] = (value >> 8) & 0xFF;
      data[ptr++] = value & 0xFF;
    }
  }
}

/// Long field (32-bit).
class FieldLong extends FieldBase {
  FieldLong(int tag, int value) : super(tag, 4, 1) {
    data = Uint8List(4);
    data[0] = (value >> 24) & 0xFF;
    data[1] = (value >> 16) & 0xFF;
    data[2] = (value >> 8) & 0xFF;
    data[3] = value & 0xFF;
  }

  FieldLong.fromList(int tag, List<int> values) : super(tag, 4, values.length) {
    data = Uint8List(values.length * 4);
    int ptr = 0;
    for (final value in values) {
      data[ptr++] = (value >> 24) & 0xFF;
      data[ptr++] = (value >> 16) & 0xFF;
      data[ptr++] = (value >> 8) & 0xFF;
      data[ptr++] = value & 0xFF;
    }
  }
}

/// Rational field (two 32-bit values).
class FieldRational extends FieldBase {
  FieldRational(int tag, List<int> value) : this.fromList(tag, [value]);

  FieldRational.fromList(int tag, List<List<int>> values)
      : super(tag, 5, values.length) {
    data = Uint8List(values.length * 8);
    int ptr = 0;
    for (final value in values) {
      data[ptr++] = (value[0] >> 24) & 0xFF;
      data[ptr++] = (value[0] >> 16) & 0xFF;
      data[ptr++] = (value[0] >> 8) & 0xFF;
      data[ptr++] = value[0] & 0xFF;
      data[ptr++] = (value[1] >> 24) & 0xFF;
      data[ptr++] = (value[1] >> 16) & 0xFF;
      data[ptr++] = (value[1] >> 8) & 0xFF;
      data[ptr++] = value[1] & 0xFF;
    }
  }
}

/// Byte field.
class FieldByte extends FieldBase {
  FieldByte(int tag, Uint8List values) : super(tag, 1, values.length) {
    data = values;
  }
}

/// Undefined field.
class FieldUndefined extends FieldBase {
  FieldUndefined(int tag, Uint8List values) : super(tag, 7, values.length) {
    data = values;
  }
}

/// Image data field (strip offset).
class FieldImage extends FieldBase {
  FieldImage(Uint8List values)
      : super(TiffConstants.tifftagStripoffsets, 4, 1) {
    data = values;
  }
}

/// ASCII field.
class FieldAscii extends FieldBase {
  FieldAscii(int tag, String value) : super(tag, 2, value.length + 1) {
    final bytes = value.codeUnits;
    data = Uint8List(bytes.length + 1);
    for (int i = 0; i < bytes.length; i++) {
      data[i] = bytes[i] & 0xFF;
    }
    // Null terminator already 0
  }
}
