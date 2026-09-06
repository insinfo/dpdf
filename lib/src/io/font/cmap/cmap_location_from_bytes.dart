import 'dart:typed_data';
import '../../source/pdf_tokenizer.dart';
import '../../source/random_access_file_or_array.dart';
import 'cmap_location.dart';

class CraftCMapLocationFromBytes implements CraftCMapLocation {
  final Uint8List data;

  CraftCMapLocationFromBytes(this.data);

  @override
  Future<CraftPdfTokenizer> getLocation(String location) async {
    return CraftPdfTokenizer(CraftRandomAccessFileOrArray(data));
  }

  @override
  CraftPdfTokenizer getLocationSync(String location) {
    return CraftPdfTokenizer(CraftRandomAccessFileOrArray(data));
  }
}
