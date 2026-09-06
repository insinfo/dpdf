import 'dart:typed_data';
import '../../io/font/cjk_resource_loader.dart';
import '../../io/font/cmap/cmap_cid_to_codepoint.dart';

class CPDF_CID2UnicodeMap {
  CMapCidToCodepoint? _cmap;

  CPDF_CID2UnicodeMap();

  static Future<CPDF_CID2UnicodeMap> load(
      String registry, String ordering) async {
    CPDF_CID2UnicodeMap map = CPDF_CID2UnicodeMap();
    String? uniMapName = _getCompatibleUniMap(registry, ordering);
    if (uniMapName != null) {
      map._cmap = await CjkResourceLoader.getCidToCodepointCmap(uniMapName);
    }
    return map;
  }

  static CPDF_CID2UnicodeMap loadSync(String registry, String ordering) {
    CPDF_CID2UnicodeMap map = CPDF_CID2UnicodeMap();
    String? uniMapName = _getCompatibleUniMap(registry, ordering);
    if (uniMapName != null) {
      map._cmap = CjkResourceLoader.getCidToCodepointCmapSync(uniMapName);
    }
    return map;
  }

  static String? _getCompatibleUniMap(String registry, String ordering) {
    if (registry == "Adobe") {
      if (ordering == "Japan1") return "Adobe-Japan1-UCS2";
      if (ordering == "Korea1") return "Adobe-Korea1-UCS2";
      if (ordering == "GB1") return "Adobe-GB1-UCS2";
      if (ordering == "CNS1") return "Adobe-CNS1-UCS2";
    }
    return null;
  }

  int unicodeFromCID(int cid) {
    if (_cmap == null) return 0;
    Uint8List bytes = _cmap!.lookup(cid);
    if (bytes.isEmpty) return 0;
    if (bytes.length == 2) {
      return (bytes[0] << 8) | bytes[1];
    } else if (bytes.length == 4) {
      // UTF-32 or similar?  usually returns 2 bytes for UCS2.
      return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    }
    return 0;
  }

  bool isLoaded() => _cmap != null;
}
