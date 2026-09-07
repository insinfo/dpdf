import 'dart:typed_data';

import '../../source/pdf_tokenizer.dart';
import '../../source/random_access_file_or_array.dart';
import '../../../platform/io.dart';
import '../cjk_resource_provider.dart';
import 'cmap_location.dart';

/// CMap location backed by a consumer-provided CJK resource provider.
class CMapLocationFromProvider implements CMapLocation {
  final CjkResourceProvider provider;

  CMapLocationFromProvider(this.provider);

  @override
  Future<PdfTokenizer> getLocation(String location) async =>
      _tokenizer(location, await provider.read(location));

  @override
  PdfTokenizer getLocationSync(String location) =>
      _tokenizer(location, provider.readSync(location));

  PdfTokenizer _tokenizer(String location, List<int>? bytes) {
    if (bytes == null) {
      throw FileSystemException('CMap resource not found', location);
    }
    return PdfTokenizer(RandomAccessFileOrArray(Uint8List.fromList(bytes)));
  }
}
