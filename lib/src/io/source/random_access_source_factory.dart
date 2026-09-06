import 'dart:typed_data';
import 'package:dpdf/src/io/source/array_random_access_source.dart';
import 'package:dpdf/src/io/source/i_random_access_source.dart';

class RandomAccessSourceFactory {
  IRandomAccessSource createSource(Uint8List data) {
    return ArrayRandomAccessSource(data);
  }
}
