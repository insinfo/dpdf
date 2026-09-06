import 'dart:typed_data';
import '../../util/int_hashtable.dart';
import 'abstract_cmap.dart';
import 'cmap_object.dart';

class CMapCidToCodepoint extends AbstractCMap {
  static final Uint8List _empty = Uint8List(0);

  final Map<int, Uint8List> map = {};
  final List<Uint8List> codeSpaceRanges = [];

  @override
  void addChar(String mark, CMapObject code) {
    if (code.isNumber()) {
      Uint8List ser = AbstractCMap.decodeStringToByte(mark);
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

  IntHashtable getReversMap() {
    IntHashtable code2cid = IntHashtable.withInitialCapacity(map.length);
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
  void addCodeSpaceRange(Uint8List low, Uint8List high) {
    codeSpaceRanges.add(low);
    codeSpaceRanges.add(high);
  }
}
