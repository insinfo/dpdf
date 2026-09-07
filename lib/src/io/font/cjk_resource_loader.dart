import '../../platform/io.dart';
import 'dart:typed_data';
import '../../commons/utils/properties.dart';
import '../util/int_hashtable.dart';
import '../util/string_tokenizer.dart';
import 'cmap/cmap_location_resource.dart';
import 'cmap/cmap_location_from_provider.dart';
import 'cmap/cmap_location.dart';
import 'cmap/cmap_parser.dart';
import 'cmap/abstract_cmap.dart';
import 'cmap/cmap_cid_uni.dart';
import 'cmap/cmap_uni_cid.dart';
import 'cmap/cmap_cid_to_codepoint.dart';
import 'cmap/cmap_codepoint_to_cid.dart';
import 'cjk_resource_provider.dart';

/// This class is responsible for loading and handling CJK fonts and CMaps.
class CjkResourceLoader {
  static final Map<String, Map<String, dynamic>> allCidFonts = {};
  static final Map<String, Set<String>> registryNames = {};

  static const String CJK_REGISTRY_FILENAME = "cjk_registry.properties";
  static const String FONTS_PROP = "fonts";
  static const String REGISTRY_PROP = "Registry";
  static const String W_PROP = "W";
  static const String W2_PROP = "W2";

  static CMapLocationResource cmapLocation = CMapLocationResource();
  static CjkResourceProvider? _resourceProvider;
  static CMapLocation? _providerCmapLocation;
  static bool _loaded = false;

  CjkResourceLoader._();

  /// Installs resources supplied by the application, or restores path-based
  /// loading when [provider] is null. Existing CJK caches are discarded.
  static void setResourceProvider(CjkResourceProvider? provider) {
    _resourceProvider = provider;
    _providerCmapLocation =
        provider == null ? null : CMapLocationFromProvider(provider);
    reset();
  }

  /// The active CMap source, including an installed in-memory provider.
  static CMapLocation get activeCmapLocation =>
      _providerCmapLocation ?? cmapLocation;

  /// Clears loaded registry and font metadata without changing the provider.
  static void reset() {
    _loaded = false;
    registryNames.clear();
    allCidFonts.clear();
  }

  static Future<void> init() async {
    if (_loaded) return;
    await loadRegistry();
    _loaded = true;
  }

  static Future<void> loadRegistry() async {
    registryNames.clear();
    allCidFonts.clear();

    final p = Properties();
    try {
      final bytes = await _readResource(CJK_REGISTRY_FILENAME);
      if (bytes == null) return;
      p.loadFromBytes(bytes);
    } catch (e) {
      // ignore
      return;
    }

    for (final entry in p) {
      final value = entry.value;
      final splitValue = value.split(" ");
      final set = <String>{};
      for (final s in splitValue) {
        if (s.isNotEmpty) {
          set.add(s);
        }
      }
      registryNames[entry.key] = set;
    }

    final fonts = registryNames[FONTS_PROP] ?? {};
    for (final font in fonts) {
      allCidFonts[font] = await readFontProperties(font);
    }
  }

  static Future<Map<String, dynamic>> readFontProperties(String name) async {
    final p = Properties();
    try {
      final bytes = await _readResource('$name.properties');
      if (bytes == null) return {};
      p.loadFromBytes(bytes);
    } catch (e) {
      return {};
    }

    final fontProperties = <String, dynamic>{};
    for (final entry in p) {
      fontProperties[entry.key] = entry.value;
    }

    if (fontProperties.containsKey(W_PROP)) {
      fontProperties[W_PROP] = createMetric(fontProperties[W_PROP] as String);
    }
    if (fontProperties.containsKey(W2_PROP)) {
      fontProperties[W2_PROP] = createMetric(fontProperties[W2_PROP] as String);
    }
    return fontProperties;
  }

  static IntHashtable createMetric(String s) {
    final h = IntHashtable();
    final tk = StringTokenizer(s);
    while (tk.hasMoreTokens()) {
      try {
        final n1 = int.parse(tk.nextToken());
        if (tk.hasMoreTokens()) {
          h.put(n1, int.parse(tk.nextToken()));
        }
      } catch (e) {
        // ignore
      }
    }
    return h;
  }

  static Future<CMapCidUni> getCid2UniCmap(String cmap) async {
    await init();
    final cidUni = CMapCidUni();
    return await _parseCmap(cmap, cidUni);
  }

  static Future<CMapUniCid> getUni2CidCmap(String uniMap) async {
    await init();
    final uniCid = CMapUniCid();
    return await _parseCmap(uniMap, uniCid);
  }

  static Future<T> _parseCmap<T extends AbstractCMap>(
      String name, T cmap) async {
    await CMapParser.loadCidMappings(name, cmap, activeCmapLocation);
    return cmap;
  }

  static void initSync() {
    if (_loaded) return;
    loadRegistrySync();
    _loaded = true;
  }

  static void loadRegistrySync() {
    registryNames.clear();
    allCidFonts.clear();

    final p = Properties();
    try {
      final bytes = _readResourceSync(CJK_REGISTRY_FILENAME);
      if (bytes == null) return;
      p.loadFromBytes(bytes);
    } catch (e) {
      return;
    }

    for (final entry in p) {
      final value = entry.value;
      final splitValue = value.split(" ");
      final set = <String>{};
      for (final s in splitValue) {
        if (s.isNotEmpty) {
          set.add(s);
        }
      }
      registryNames[entry.key] = set;
    }

    final fonts = registryNames[FONTS_PROP] ?? {};
    for (final font in fonts) {
      allCidFonts[font] = readFontPropertiesSync(font);
    }
  }

  static Map<String, dynamic> readFontPropertiesSync(String name) {
    final p = Properties();
    try {
      final bytes = _readResourceSync('$name.properties');
      if (bytes == null) return {};
      p.loadFromBytes(bytes);
    } catch (e) {
      return {};
    }

    final fontProperties = <String, dynamic>{};
    for (final entry in p) {
      fontProperties[entry.key] = entry.value;
    }

    if (fontProperties.containsKey(W_PROP)) {
      fontProperties[W_PROP] = createMetric(fontProperties[W_PROP] as String);
    }
    if (fontProperties.containsKey(W2_PROP)) {
      fontProperties[W2_PROP] = createMetric(fontProperties[W2_PROP] as String);
    }
    return fontProperties;
  }

  static CMapCidUni getCid2UniCmapSync(String cmap) {
    initSync();
    final cidUni = CMapCidUni();
    _parseCmapSync(cmap, cidUni);
    return cidUni;
  }

  static CMapUniCid getUni2CidCmapSync(String uniMap) {
    initSync();
    final uniCid = CMapUniCid();
    _parseCmapSync(uniMap, uniCid);
    return uniCid;
  }

  static CMapCidToCodepoint getCidToCodepointCmapSync(String cmap) {
    initSync();
    final cidByte = CMapCidToCodepoint();
    _parseCmapSync(cmap, cidByte);
    return cidByte;
  }

  static CMapCodepointToCid getCodepointToCidCmapSync(String uniMap) {
    initSync();
    final cp2cid = CMapCodepointToCid();
    _parseCmapSync(uniMap, cp2cid);
    return cp2cid;
  }

  static Future<CMapCidToCodepoint> getCidToCodepointCmap(String cmap) async {
    await init();
    final cidByte = CMapCidToCodepoint();
    return await _parseCmap(cmap, cidByte);
  }

  static Future<CMapCodepointToCid> getCodepointToCidCmap(String uniMap) async {
    await init();
    final cp2cid = CMapCodepointToCid();
    return await _parseCmap(uniMap, cp2cid);
  }

  static void _parseCmapSync<T extends AbstractCMap>(String name, T cmap) {
    CMapParser.loadCidMappingsSync(name, cmap, activeCmapLocation);
  }

  static Future<Uint8List?> _readResource(String name) async {
    final provider = _resourceProvider;
    if (provider != null) return provider.read(name);
    final file = File(cmapLocation.getLocationPath() + name);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  static Uint8List? _readResourceSync(String name) {
    final provider = _resourceProvider;
    if (provider != null) return provider.readSync(name);
    final file = File(cmapLocation.getLocationPath() + name);
    if (!file.existsSync()) return null;
    return file.readAsBytesSync();
  }
}
