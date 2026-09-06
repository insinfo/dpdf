import 'dart:typed_data';
import '../../source/pdf_tokenizer.dart';
import '../../source/random_access_file_or_array.dart';
import 'i_cmap_location.dart';

class CMapLocationFromBytes implements ICMapLocation {
  final Uint8List data;

  CMapLocationFromBytes(this.data);

  @override
  Future<PdfTokenizer> getLocation(String location) async {
    return PdfTokenizer(RandomAccessFileOrArray(data));
  }

  @override
  PdfTokenizer getLocationSync(String location) {
    return PdfTokenizer(RandomAccessFileOrArray(data));
  }
}
