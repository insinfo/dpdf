import 'dart:typed_data';

import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'package:dpdf/src/io/codec/tiff_field.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';

class TiffDirectory {
  bool isBigEndian = false;
  int numEntries = 0;
  List<TiffField> fields = [];
  Map<int, int> fieldIndex = {};
  int ifdOffset = 8;
  int nextIfdOffset = 0;

  static const List<int> sizeOfType = [
    0, //  0 = n/a
    1, //  1 = byte
    1, //  2 = ascii
    2, //  3 = short
    4, //  4 = long
    8, //  5 = rational
    1, //  6 = sbyte
    1, //  7 = undefined
    2, //  8 = sshort
    4, //  9 = slong
    8, // 10 = srational
    4, // 11 = float
    8 // 12 = double
  ];

  TiffDirectory(RandomAccessFileOrArray stream,
      {int directory = 0, int? ifdOffset}) {
    int globalSaveOffset = stream.getPosition();
    stream.seek(0);
    int endian = stream.readUnsignedShort();
    if (!isValidEndianTag(endian)) {
      throw IoException("Bad endianness tag (not 0x4949 or 0x4d4d).");
    }
    isBigEndian = (endian == 0x4d4d);

    int magic = readUnsignedShort(stream);
    if (magic != 42) {
      throw IoException("Bad magic number, should be 42.");
    }

    // Get the initial ifd offset
    int ifdOffsetLocal = readUnsignedInt(stream);

    if (ifdOffset != null) {
      // ifdOffset provided, seek to it
      ifdOffsetLocal = ifdOffset;
      int dirNum = 0;
      while (dirNum < directory) {
        stream.seek(ifdOffsetLocal);
        int numEntries = readUnsignedShort(stream);
        stream.seek(ifdOffsetLocal + 12 * numEntries);
        ifdOffsetLocal = readUnsignedInt(stream);
        dirNum++;
      }
    } else {
      // Standard directory traversal
      for (int i = 0; i < directory; i++) {
        if (ifdOffsetLocal == 0) {
          throw IoException("Directory number too large.");
        }
        stream.seek(ifdOffsetLocal);
        int entries = readUnsignedShort(stream);
        stream.skip(12 * entries);
        ifdOffsetLocal = readUnsignedInt(stream);
      }
    }

    stream.seek(ifdOffsetLocal);
    initialize(stream);
    stream.seek(globalSaveOffset);
  }

  static bool isValidEndianTag(int endian) {
    return endian == 0x4949 || endian == 0x4d4d;
  }

  void initialize(RandomAccessFileOrArray stream) {
    int nextTagOffset = 0;
    int maxOffset = stream.length().toInt();

    ifdOffset = stream.getPosition().toInt();
    numEntries = readUnsignedShort(stream);
    fields = List.filled(numEntries, TiffField(0, 0, 0, null));
    // Using filled with dummy, will replace.
    // Actually better to use growable list and clear?
    // fields array needs to strictly match numEntries?
    // The C# code creates array of size numEntries.

    for (int i = 0; i < numEntries; i++) {
      int tag = readUnsignedShort(stream);
      int type = readUnsignedShort(stream);
      int count = readUnsignedInt(stream);
      bool processTag = true;

      nextTagOffset = stream.getPosition().toInt() + 4;

      try {
        if (count * sizeOfType[type] > 4) {
          int valueOffset = readUnsignedInt(stream);
          if (valueOffset < maxOffset) {
            stream.seek(valueOffset);
          } else {
            processTag = false;
          }
        }
      } catch (e) {
        processTag = false;
      }

      if (processTag) {
        fieldIndex[tag] = i;
        dynamic obj;
        switch (type) {
          case TiffField.TIFF_BYTE:
          case TiffField.TIFF_SBYTE:
          case TiffField.TIFF_UNDEFINED:
            Uint8List bvalues = Uint8List(count);
            stream.readFully(bvalues);
            if (type == TiffField.TIFF_SBYTE) {
              obj = Int8List.view(bvalues.buffer);
            } else {
              obj = bvalues;
            }
            // if (type == TiffField.TIFF_ASCII) {
            //   // Handled separately? NO C# code merges byte/sbyte/undefined/ascii in one block?
            //   // Actually C# has case TIFF_ASCII separately.
            // }
            break;
          case TiffField.TIFF_ASCII:
            Uint8List bvalues = Uint8List(count);
            stream.readFully(bvalues);
            List<String> v = [];
            int index = 0;
            int prevIndex = 0;
            while (index < count) {
              while (index < count && bvalues[index] != 0) {
                index++;
              }
              // Decode string
              // For simplicity assume Latin1 or UTF8?
              //  uses StringForBytes.
              String s =
                  String.fromCharCodes(bvalues.sublist(prevIndex, index));
              v.add(s);
              index++;
              prevIndex = index;
            }
            obj = v;
            break;
          case TiffField.TIFF_SHORT:
            Uint16List cvalues = Uint16List(count);
            for (int j = 0; j < count; j++)
              cvalues[j] = readUnsignedShort(stream);
            obj = cvalues;
            break;
          case TiffField.TIFF_LONG:
            // Using Int64List for longs to be safe, or Uint32List if we strictly follow 32-bit unsigned?
            // ReadUnsignedInt returns long (Dart int).
            // Let's use List<int> for simplicity or Uint32List?
            // C# uses long[]
            Int64List lvalues = Int64List(count);
            for (int j = 0; j < count; j++)
              lvalues[j] = readUnsignedInt(stream);
            obj = lvalues;
            break;
          case TiffField.TIFF_RATIONAL:
            List<List<int>> llvalues = List.generate(count, (_) => [0, 0]);
            for (int j = 0; j < count; j++) {
              llvalues[j][0] = readUnsignedInt(stream);
              llvalues[j][1] = readUnsignedInt(stream);
            }
            obj = llvalues;
            break;
          case TiffField.TIFF_SSHORT:
            Int16List svalues = Int16List(count);
            for (int j = 0; j < count; j++) svalues[j] = readShort(stream);
            obj = svalues;
            break;
          case TiffField.TIFF_SLONG:
            Int32List ivalues = Int32List(count);
            for (int j = 0; j < count; j++) ivalues[j] = readInt(stream);
            obj = ivalues;
            break;
          case TiffField.TIFF_SRATIONAL:
            List<List<int>> iivalues = List.generate(count, (_) => [0, 0]);
            for (int j = 0; j < count; j++) {
              iivalues[j][0] = readInt(stream);
              iivalues[j][1] = readInt(stream);
            }
            obj = iivalues;
            break;
          case TiffField.TIFF_FLOAT:
            Float32List fvalues = Float32List(count);
            for (int j = 0; j < count; j++) fvalues[j] = readFloat(stream);
            obj = fvalues;
            break;
          case TiffField.TIFF_DOUBLE:
            Float64List dvalues = Float64List(count);
            for (int j = 0; j < count; j++) dvalues[j] = readDouble(stream);
            obj = dvalues;
            break;
          default:
            // Skip
            break;
        }
        fields[i] = TiffField(tag, type, count, obj);
      }

      stream.seek(nextTagOffset);
    }

    try {
      nextIfdOffset = readUnsignedInt(stream);
    } catch (e) {
      nextIfdOffset = 0;
    }
  }

  // Primitive readers
  int readShort(RandomAccessFileOrArray stream) {
    if (isBigEndian) return stream.readShort();
    return stream.readShortLE();
  }

  int readUnsignedShort(RandomAccessFileOrArray stream) {
    if (isBigEndian) return stream.readUnsignedShort();
    return stream.readUnsignedShortLE();
  }

  int readInt(RandomAccessFileOrArray stream) {
    if (isBigEndian) return stream.readInt();
    return stream.readIntLE();
  }

  int readUnsignedInt(RandomAccessFileOrArray stream) {
    if (isBigEndian) return stream.readUnsignedInt();
    return stream.readUnsignedIntLE();
  }

  double readFloat(RandomAccessFileOrArray stream) {
    if (isBigEndian) return stream.readFloat();
    return stream.readFloatLE();
  }

  double readDouble(RandomAccessFileOrArray stream) {
    if (isBigEndian) return stream.readDouble();
    return stream.readDoubleLE();
  }

  // Public API
  int? getNumEntries() => numEntries;

  TiffField? getField(int tag) {
    int? i = fieldIndex[tag];
    if (i == null) return null;
    return fields[i];
  }

  bool isTagPresent(int tag) {
    return fieldIndex.containsKey(tag);
  }

  int getFieldAsLong(int tag, [int index = 0]) {
    TiffField? f = getField(tag);
    return f?.getAsLong(index) ?? 0;
  }

  int getFieldAsInt(int tag, [int index = 0]) {
    TiffField? f = getField(tag);
    return f?.getAsInt(index) ?? 0;
  }

  // Static Helper
  static int getNumDirectories(RandomAccessFileOrArray stream) {
    int pointer = stream.getPosition();
    stream.seek(0);
    int endian = stream.readUnsignedShort();
    if (!isValidEndianTag(endian)) throw IoException("Bad endianness.");
    bool isBig = (endian == 0x4d4d);

    int magic =
        isBig ? stream.readUnsignedShort() : stream.readUnsignedShortLE();
    if (magic != 42) throw IoException("Bad magic.");

    stream.seek(4);
    int offset = isBig ? stream.readUnsignedInt() : stream.readUnsignedIntLE();

    int num = 0;
    while (offset != 0) {
      num++;
      try {
        stream.seek(offset);
        int entries =
            isBig ? stream.readUnsignedShort() : stream.readUnsignedShortLE();
        stream.skip(12 * entries);
        offset = isBig ? stream.readUnsignedInt() : stream.readUnsignedIntLE();
      } catch (e) {
        num--;
        break;
      }
    }
    stream.seek(pointer);
    return num;
  }
}
