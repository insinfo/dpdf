import '../../util/int_hashtable.dart';
import 'abstract_cmap.dart';
import 'cmap_cid_to_codepoint.dart';
import 'cmap_object.dart';

class CraftCMapCodepointToCid extends CraftAbstractCMap {
  late final CraftIntHashtable map;

  CraftCMapCodepointToCid() {
    map = CraftIntHashtable();
  }

  CraftCMapCodepointToCid.fromReverseMap(CraftCMapCidToCodepoint reverseMap) {
    map = reverseMap.getReversMap();
  }

  @override
  void registerMappedCode(String mark, CraftCMapObject code) {
    if (code.isNumber()) {
      List<int> ser = CraftAbstractCMap.mappingCodeBytes(mark);
      int byteCode = 0;
      for (int b in ser) {
        byteCode <<= 8;
        byteCode += b & 0xFF;
      }
      map.put(byteCode, code.getValue() as int);
    }
  }

  int lookup(int codepoint) {
    return map.get(codepoint);
  }

  bool isEmpty() => map.isEmpty();
}
