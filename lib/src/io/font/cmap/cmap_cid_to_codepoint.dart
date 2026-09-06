import 'dart:typed_data';
import '../../util/int_hashtable.dart';
import 'abstract_cmap.dart';
import 'cmap_object.dart';

class CraftCMapCidToCodepoint extends CraftAbstractCMap {
  static final Uint8List _empty = Uint8List(0);

  final Map<int, Uint8List> map = {};
  final List<Uint8List> codeSpaceRanges = [];

  @override
  void registerMappedCode(String mark, CraftCMapObject code) {
    if (code.isNumber()) {
      Uint8List ser = CraftAbstractCMap.mappingCodeBytes(mark);
      map[code.getValue() as int] = ser;
    }
  }

  Uint8List lookup(int cid) {
    Uint8List? ser = map[cid];
    if (ser == null) {
      return _empty;
    } else {
      return ser;
    }
  }

  CraftIntHashtable getReversMap() {
    CraftIntHashtable code2cid =
        CraftIntHashtable.withInitialCapacity(map.length);
    for (var entry in map.entries) {
      Uint8List bytes = entry.value;
      int byteCode = 0;
      for (int b in bytes) {
        byteCode <<= 8;
        byteCode += b & 0xFF;
      }
      code2cid.put(byteCode, entry.key);
    }
    return code2cid;
  }

  List<Uint8List> getCodeSpaceRanges() {
    return codeSpaceRanges;
  }

  @override
  void registerCodeInterval(Uint8List low, Uint8List high) {
    codeSpaceRanges.add(low);
    codeSpaceRanges.add(high);
  }
}
