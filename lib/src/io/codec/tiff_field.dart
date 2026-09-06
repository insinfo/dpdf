import 'dart:typed_data';

class TiffField implements Comparable<TiffField> {
  static const int TIFF_BYTE = 1;
  static const int TIFF_ASCII = 2;
  static const int TIFF_SHORT = 3;
  static const int TIFF_LONG = 4;
  static const int TIFF_RATIONAL = 5;
  static const int TIFF_SBYTE = 6;
  static const int TIFF_UNDEFINED = 7;
  static const int TIFF_SSHORT = 8;
  static const int TIFF_SLONG = 9;
  static const int TIFF_SRATIONAL = 10;
  static const int TIFF_FLOAT = 11;
  static const int TIFF_DOUBLE = 12;

  // Aliases for compatibility
  static const int tiffByte = TIFF_BYTE;
  static const int tiffAscii = TIFF_ASCII;
  static const int tiffShort = TIFF_SHORT;
  static const int tiffLong = TIFF_LONG;
  static const int tiffRational = TIFF_RATIONAL;
  static const int tiffSbyte = TIFF_SBYTE;
  static const int tiffUndefined = TIFF_UNDEFINED;
  static const int tiffSshort = TIFF_SSHORT;
  static const int tiffSlong = TIFF_SLONG;
  static const int tiffSrational = TIFF_SRATIONAL;
  static const int tiffFloat = TIFF_FLOAT;
  static const int tiffDouble = TIFF_DOUBLE;

  int getType() => type;

  List<int> getAsRational(int index) {
    return getAsRationals()[index];
  }

  int tag;
  int type;
  int count;
  dynamic data;

  TiffField(this.tag, this.type, this.count, this.data);

  int getTag() {
    return tag;
  }

  int getFieldType() {
    return type;
  }

  int getCount() {
    return count;
  }

  Uint8List getAsBytes() {
    return data as Uint8List;
  }

  Uint16List getAsChars() {
    return data as Uint16List;
  }

  Int16List getAsShorts() {
    return data as Int16List;
  }

  Int32List getAsInts() {
    return data as Int32List;
  }

  Int64List getAsLongs() {
    // In Dart, we might use List<int> for longs if Int64List is not standard (it is in typed_data)
    return data as Int64List;
  }

  Float32List getAsFloats() {
    return data as Float32List;
  }

  Float64List getAsDoubles() {
    return data as Float64List;
  }

  List<String> getAsStrings() {
    return data as List<String>;
  }

  List<List<int>> getAsSRationals() {
    return data as List<List<int>>;
  }

  List<List<int>> getAsRationals() {
    // Actually longs in C# (64 bit), so List<List<int>> in Dart
    return data as List<List<int>>;
  }

  int getAsInt(int index) {
    switch (type) {
      case TIFF_BYTE:
      case TIFF_UNDEFINED:
        return (data as Uint8List)[index];
      case TIFF_SBYTE:
        return (data as Int8List)[index];
      case TIFF_SHORT:
        return (data as Uint16List)[index];
      case TIFF_SSHORT:
        return (data as Int16List)[index];
      case TIFF_SLONG:
        return (data as Int32List)[index];
      default:
        throw Exception("Invalid cast");
    }
  }

  int getAsLong(int index) {
    switch (type) {
      case TIFF_BYTE:
      case TIFF_UNDEFINED:
        return (data as Uint8List)[index];
      case TIFF_SBYTE:
        return (data as Int8List)[index];
      case TIFF_SHORT:
        return (data as Uint16List)[index];
      case TIFF_SSHORT:
        return (data as Int16List)[index];
      case TIFF_SLONG:
        return (data as Int32List)[index];
      case TIFF_LONG:
        // Using generic List for Longs if Int64List is not used consistently
        if (data is Int64List) return (data as Int64List)[index];
        if (data is Uint32List) return (data as Uint32List)[index];
        return (data as List<int>)[index];
      default:
        throw Exception("Invalid cast");
    }
  }

  double getAsFloat(int index) {
    switch (type) {
      case TIFF_FLOAT:
        return (data as Float32List)[index];
      case TIFF_DOUBLE:
        return (data as Float64List)[index];
      case TIFF_SRATIONAL:
        var val = getAsSRationals()[index];
        return val[0] / val[1];
      case TIFF_RATIONAL:
        var val2 = getAsRationals()[index];
        return val2[0] / val2[1];
      default:
        return getAsLong(index).toDouble();
    }
  }

  double getAsDouble(int index) {
    return getAsFloat(index); // Simplification
  }

  @override
  int compareTo(TiffField other) {
    if (tag < other.tag) return -1;
    if (tag > other.tag) return 1;
    return 0;
  }
}
