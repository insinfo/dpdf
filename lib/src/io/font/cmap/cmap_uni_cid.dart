import '../../util/int_hashtable.dart';
import '../../util/text_util.dart';
import 'abstract_cmap.dart';
import 'cmap_object.dart';
import 'cmap_to_unicode.dart';

class CMapUniCid extends AbstractCMap {
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
      map.put(codePoint, code.getValue() as int);
    }
  }

  int lookup(int character) {
    return map.get(character);
  }

  CMapToUnicode exportToUnicode() {
    CMapToUnicode uni = CMapToUnicode();
    List<int> keys = map.toOrderedKeys();
    for (int key in keys) {
      uni.addCharInt(
          map.get(key), String.fromCharCodes(TextUtil.convertFromUtf32(key)));
    }
    int spaceCid = lookup(32);
    if (spaceCid != 0) {
      uni.addCharInt(
          spaceCid, String.fromCharCodes(TextUtil.convertFromUtf32(32)));
    }
    return uni;
  }

  List<int> getCodePoints() {
    return map.getKeys();
  }
}
