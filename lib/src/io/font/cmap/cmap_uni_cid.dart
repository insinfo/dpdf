import '../../util/int_hashtable.dart';
import 'unicode_mapping_scalar.dart';
import 'abstract_cmap.dart';
import 'cmap_object.dart';
import 'cmap_to_unicode.dart';

class CMapUniCid extends AbstractCMap {
  final IntHashtable map = IntHashtable.withInitialCapacity(65537);

  @override
  void registerMappedCode(String mark, CMapObject code) {
    if (!code.isNumber()) return;
    final cid = code.getValue();
    if (cid is! int || cid < 0 || cid > 0xffff) {
      throw FormatException(
          'Character identifier must be an unsigned 16-bit value.');
    }
    final scalar = unicodeMappingScalar(mark);
    map.put(scalar, cid);
  }

  int lookup(int character) {
    return map.get(character);
  }

  CMapToUnicode exportToUnicode() {
    CMapToUnicode uni = CMapToUnicode();
    List<int> keys = map.toOrderedKeys();
    for (int key in keys) {
      uni.addCharInt(map.get(key), String.fromCharCode(key));
    }
    int spaceCid = lookup(32);
    if (spaceCid != 0) {
      uni.addCharInt(spaceCid, String.fromCharCode(32));
    }
    return uni;
  }

  List<int> getCodePoints() {
    return map.getKeys();
  }
}
