import '../../io/font/cmap/cmap_location.dart';
import '../../io/font/cmap/cmap_parser.dart';
import 'unicode_code_map.dart';

/// Immutable CID-to-Unicode strings, including supplementary characters and
/// multi-character destinations. Resource data is supplied by the caller.
class CidUnicodeTable {
  final Map<int, String> _values;

  CidUnicodeTable._(UnicodeCodeMap map) : _values = map.mappings;

  factory CidUnicodeTable.fromMappings(Map<int, String> mappings) {
    final map = UnicodeCodeMap();
    for (final entry in mappings.entries) {
      map.setMapping(entry.key, entry.value);
    }
    return CidUnicodeTable._(map);
  }

  String textForCid(int cid) => _values[cid] ?? '';

  int? scalarForCid(int cid) {
    final scalars = textForCid(cid).runes;
    return scalars.length == 1 ? scalars.first : null;
  }

  bool get isEmpty => _values.isEmpty;

  static Future<CidUnicodeTable> read(
      String resourceName, CraftCMapLocation location) async {
    final map = UnicodeCodeMap();
    await CraftCMapParser.loadCidMappings(resourceName, map, location);
    return CidUnicodeTable._(map);
  }

  static CidUnicodeTable readSync(
      String resourceName, CraftCMapLocation location) {
    final map = UnicodeCodeMap();
    CraftCMapParser.loadCidMappingsSync(resourceName, map, location);
    return CidUnicodeTable._(map);
  }
}
