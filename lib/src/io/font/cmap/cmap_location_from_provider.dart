import 'dart:typed_data';

import '../../source/pdf_tokenizer.dart';
import '../../source/random_access_file_or_array.dart';
import '../../../platform/io.dart';
import '../cjk_resource_provider.dart';
import 'cmap_location.dart';

/// CMap location backed by a consumer-provided CJK resource provider.
class CraftCMapLocationFromProvider implements CraftCMapLocation {
  final CraftCjkResourceProvider provider;

  CraftCMapLocationFromProvider(this.provider);

  @override
  Future<CraftPdfTokenizer> getLocation(String location) async =>
      _tokenizer(location, await provider.read(location));

  @override
  CraftPdfTokenizer getLocationSync(String location) =>
      _tokenizer(location, provider.readSync(location));

  CraftPdfTokenizer _tokenizer(String location, List<int>? bytes) {
    if (bytes == null) {
      throw FileSystemException('CMap resource not found', location);
    }
    return CraftPdfTokenizer(
        CraftRandomAccessFileOrArray(Uint8List.fromList(bytes)));
  }
}
