import 'cpdf_cid2unicodemap.dart';

class CPDF_FontGlobals {
  static final CPDF_FontGlobals _instance = CPDF_FontGlobals._();
  factory CPDF_FontGlobals() => _instance;
  CPDF_FontGlobals._();

  final Map<String, CPDF_CID2UnicodeMap> _cid2UnicodeMaps = {};

  Future<CPDF_CID2UnicodeMap?> getCID2UnicodeMap(
      String registry, String ordering) async {
    String key = "$registry-$ordering";
    if (_cid2UnicodeMaps.containsKey(key)) {
      return _cid2UnicodeMaps[key];
    }
    CPDF_CID2UnicodeMap map =
        await CPDF_CID2UnicodeMap.load(registry, ordering);
    if (map.isLoaded()) {
      _cid2UnicodeMaps[key] = map;
      return map;
    }
    return null;
  }

  CPDF_CID2UnicodeMap? getCID2UnicodeMapSync(String registry, String ordering) {
    String key = "$registry-$ordering";
    if (_cid2UnicodeMaps.containsKey(key)) {
      return _cid2UnicodeMaps[key];
    }
    CPDF_CID2UnicodeMap map = CPDF_CID2UnicodeMap.loadSync(registry, ordering);
    if (map.isLoaded()) {
      _cid2UnicodeMaps[key] = map;
      return map;
    }
    return null;
  }

  void clearCache() {
    _cid2UnicodeMaps.clear();
  }
}
