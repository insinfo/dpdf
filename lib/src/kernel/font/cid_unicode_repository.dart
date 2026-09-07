import '../../io/font/cjk_resource_loader.dart';
import '../../io/font/cmap/cmap_location.dart';
import 'cid_unicode_table.dart';

/// Caches explicitly named character collections within one resource provider.
/// Unsupported collections return null; absent or invalid resources report errors.
class CidUnicodeRepository {
  static final shared = CidUnicodeRepository();
  final CraftCMapLocation? _location;
  final _completed = <(String, String), CidUnicodeTable>{};
  final _pending = <(String, String), Future<CidUnicodeTable?>>{};
  int _generation = 0;

  CidUnicodeRepository({CraftCMapLocation? location}) : _location = location;

  CraftCMapLocation get _provider =>
      _location ?? CraftCjkResourceLoader.activeCmapLocation;

  static String? _resource(String registry, String collection) {
    if (registry != 'Adobe' ||
        !const {'Japan1', 'Korea1', 'GB1', 'CNS1'}.contains(collection)) {
      return null;
    }
    return 'Adobe-$collection-UCS2';
  }

  Future<CidUnicodeTable?> loadCollection(String registry, String collection) {
    final key = (registry, collection);
    final cached = _completed[key];
    if (cached != null) return Future.value(cached);
    final name = _resource(registry, collection);
    if (name == null) return Future.value(null);
    return _pending.putIfAbsent(key, () => _read(key, name, _generation));
  }

  Future<CidUnicodeTable?> _read(
      (String, String) key, String name, int generation) async {
    try {
      final table = await CidUnicodeTable.read(name, _provider);
      if (generation == _generation) _completed[key] = table;
      return table;
    } finally {
      if (generation == _generation) _pending.remove(key);
    }
  }

  CidUnicodeTable? loadCollectionSync(String registry, String collection) {
    final key = (registry, collection);
    if (_completed.containsKey(key)) return _completed[key];
    final name = _resource(registry, collection);
    if (name == null) return null;
    return _completed[key] = CidUnicodeTable.readSync(name, _provider);
  }

  /// In-flight requests still finish for their callers, but cannot refill cache.
  void discardCachedCollections() {
    _generation++;
    _completed.clear();
    _pending.clear();
  }
}
