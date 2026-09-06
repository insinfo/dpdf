import '../../util/int_hashtable.dart';
import 'unicode_mapping_scalar.dart';
import 'abstract_cmap.dart';
import 'cmap_object.dart';

class CraftCMapCidUni extends CraftAbstractCMap {
  final CraftIntHashtable map = CraftIntHashtable.withInitialCapacity(65537);

  @override
  void registerMappedCode(String mark, CraftCMapObject code) {
    if (!code.isNumber()) return;
    final cid = code.getValue();
    if (cid is! int || cid < 0 || cid > 0xffff) {
      throw FormatException(
          'Character identifier must be an unsigned 16-bit value.');
    }
    final scalar = unicodeMappingScalar(mark);
    map.put(cid, scalar);
  }

  int lookup(int cid) {
    return map.get(cid);
  }

  List<int> getCids() {
    return map.getKeys();
  }
}
