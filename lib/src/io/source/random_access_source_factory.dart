import 'dart:typed_data';
import 'package:pdfcraft/src/io/source/array_random_access_source.dart';
import 'package:pdfcraft/src/io/source/random_access_source.dart';

class CraftRandomAccessSourceFactory {
  CraftRandomAccessSource createSource(Uint8List data) {
    return CraftArrayRandomAccessSource(data);
  }
}
