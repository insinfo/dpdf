import '../../util/int_hashtable.dart';
import '../../util/text_util.dart';
import 'abstract_cmap.dart';
import 'cmap_object.dart';

class CMapCidUni extends AbstractCMap {
  final IntHashtable map = IntHashtable.withInitialCapacity(65537);

  @override
  void addChar(String mark, CMapObject code) {
    if (code.isNumber()) {
      int codePoint;
      String s = toUnicodeString(mark, true);
      if (TextUtil.isSurrogatePair(s, 0)) {
        codePoint = TextUtil.convertToUtf32(s, 0);
      } else {
        codePoint = s.codeUnitAt(0);
      }
      map.put(code.getValue() as int, codePoint);
    }
  }

  int lookup(int cid) {
    return map.get(cid);
  }

  List<int> getCids() {
    return map.getKeys();
  }
}
