import 'dart:typed_data';
import 'dart:math' as math;
import 'package:dpdf/src/commons/utils/value_collections.dart';

/// Value conversions, collection comparisons and numeric bit representations.
class ValueUtils {
  ValueUtils._();

  static String getStringForChars(List<int> chars) {
    return String.fromCharCodes(chars);
  }

  static String getStringForCharsRange(
      List<int> chars, int offset, int length) {
    return String.fromCharCodes(chars, offset, offset + length);
  }

  static String getStringForBytes(Uint8List bytes, [int? offset, int? length]) {
    if (offset == null || length == null) {
      return String.fromCharCodes(bytes);
    }
    return String.fromCharCodes(bytes, offset, offset + length);
  }

  static int floatToIntBits(double value) {
    var bdata = ByteData(4);
    bdata.setFloat32(0, value);
    return bdata.getInt32(0);
  }

  static BigInt doubleToLongBits(double value) {
    var bdata = ByteData(8);
    bdata.setFloat64(0, value);
    return ((BigInt.from(bdata.getUint32(0)) << 32) |
            BigInt.from(bdata.getUint32(4)))
        .toSigned(64);
  }

  static double intBitsToFloat(int bits) {
    var bdata = ByteData(4);
    bdata.setInt32(0, bits);
    return bdata.getFloat32(0);
  }

  static double longBitsToDouble(BigInt bits) {
    var bdata = ByteData(8);
    final unsigned = bits.toUnsigned(64);
    bdata.setUint32(0, (unsigned >> 32).toInt());
    bdata.setUint32(4, (unsigned & BigInt.from(0xffffffff)).toInt());
    return bdata.getFloat64(0);
  }

  static String integerToHexString(int i) {
    return i.toRadixString(16);
  }

  static String integerToOctalString(int i) {
    return i.toRadixString(8);
  }

  static bool dictionariesEquals<K, V>(Map<K, V>? that, Map<K, V>? other) {
    if (identical(that, other)) return true;
    if (that == null || other == null) return false;
    return ValueCollections.mapsEqual(that, other);
  }

  static int dictionaryHashCode<K, V>(Map<K, V>? dict) {
    if (dict == null) return 0;
    return ValueCollections.mapHash(dict);
  }

  static bool setEquals<T>(Set<T>? that, Set<T>? other) {
    if (identical(that, other)) return true;
    if (that == null || other == null) return false;
    return ValueCollections.setsEqual(that, other);
  }

  static int setHashCode<T>(Set<T>? set) {
    if (set == null) return 0;
    return ValueCollections.setHash(set);
  }

  static bool arraysEquals<T>(List<T>? a, List<T>? a2) {
    if (identical(a, a2)) return true;
    if (a == null || a2 == null) return false;
    return ValueCollections.listsEqual(a, a2);
  }

  static int arraysHashCode<T>(List<T>? a) {
    if (a == null) return 0;
    return ValueCollections.listHash(a);
  }

  static int objectsHashCode(List<Object?>? a) {
    if (a == null) return 0;
    int result = 1;
    for (var element in a) {
      result = 31 * result + (element == null ? 0 : element.hashCode);
    }
    return result;
  }

  static String arraysToString<T>(List<T>? a) {
    if (a == null) return "null";
    return a.toString();
  }

  static bool isValidCodePoint(int codePoint) {
    return codePoint >= 0 && codePoint <= 0x10FFFF;
  }

  static const int MIN_SUPPLEMENTARY_CODE_POINT = 0x010000;
  static const int MIN_HIGH_SURROGATE = 0xD800;
  static const int MIN_LOW_SURROGATE = 0xDC00;

  static int toCodePoint(int high, int low) {
    return ((high << 10) + low) +
        (MIN_SUPPLEMENTARY_CODE_POINT -
            (MIN_HIGH_SURROGATE << 10) -
            MIN_LOW_SURROGATE);
  }

  static List<T> arraysAsList<T>(List<T> a) {
    return a;
  }

  static String integerToString(int i) {
    return i.toString();
  }

  static double random() {
    return math.Random().nextDouble();
  }

  static void fill<T>(List<T> a, T val, [int? from, int? to]) {
    int start = from ?? 0;
    int end = to ?? a.length;
    a.fillRange(start, end, val);
  }

  static void sort<T>(List<T> array, [int? from, int? to, Comparator<T>? c]) {
    int start = from ?? 0;
    int end = to ?? array.length;
    if (start == 0 && end == array.length) {
      array.sort(c);
    } else {
      var sub = array.sublist(start, end);
      sub.sort(c);
      array.setRange(start, end, sub);
    }
  }

  static int integerCompare(int a, int b) {
    return a.compareTo(b);
  }

  static List<T> arraysCopyOf<T>(List<T> original, int newLength) {
    // In Dart, we can't easily create a generic T[] of a specific length if T is not nullable or if we don't have a factory.
    // However, for most  uses, this is fine.
    var copy = List<T?>.filled(newLength, null);
    int len = math.min(original.length, newLength);
    for (int i = 0; i < len; i++) {
      copy[i] = original[i];
    }
    return List<T>.from(copy);
  }

  static List<T> arraysCopyOfRange<T>(List<T> original, int from, int to) {
    return original.sublist(from, to);
  }
}
