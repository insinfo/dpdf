import 'dart:typed_data';

/// Helper class for array operations.
class ArrayUtil {
  ArrayUtil._();

  /// Shortens byte array to specified length.
  static Uint8List shortenArray(Uint8List src, int length) {
    if (length < src.length) {
      return Uint8List.fromList(src.sublist(0, length));
    }
    return src;
  }

  /// Converts a collection to an int list.
  static List<int> toIntArray(Iterable<int> collection) {
    return collection.toList();
  }

  /// Creates a hash of the given byte array.
  static int bytesHashCode(Uint8List? a) {
    if (a == null) return 0;
    int result = 1;
    for (final element in a) {
      result = 31 * result + element;
    }
    return result;
  }

  /// Fills a list with the given value.
  static List<int> fillIntWithValue(List<int> a, int value) {
    for (int i = 0; i < a.length; i++) {
      a[i] = value;
    }
    return a;
  }

  /// Fills a double list with the given value.
  static List<double> fillDoubleWithValue(List<double> a, double value) {
    for (int i = 0; i < a.length; i++) {
      a[i] = value;
    }
    return a;
  }

  /// Fills a generic list with the given value.
  static void fillWithValue<T>(List<T> a, T value) {
    for (int i = 0; i < a.length; i++) {
      a[i] = value;
    }
  }

  /// Clones int list.
  static List<int> cloneArray(List<int> src) {
    return List<int>.from(src);
  }

  /// Gets the index of object in array.
  static int indexOf<T>(List<T> a, T key) {
    return a.indexOf(key);
  }

  /// Creates a new list filled with a value.
  static List<int> createFilledInt(int length, int value) {
    return List<int>.filled(length, value);
  }

  /// Creates a new double list filled with a value.
  static List<double> createFilledDouble(int length, double value) {
    return List<double>.filled(length, value);
  }
}
