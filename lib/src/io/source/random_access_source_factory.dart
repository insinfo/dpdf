import 'dart:typed_data';
import 'package:dpdf/src/io/source/array_random_access_source.dart';
import 'package:dpdf/src/io/source/random_access_source.dart';

class RandomAccessSourceFactory {
  RandomAccessSource createSource(Uint8List data) {
    return ArrayRandomAccessSource(data);
  }
}
