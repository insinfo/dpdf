import 'dart:typed_data';
import 'abstract_cmap.dart';
import 'cmap_content_parser.dart';
import 'cmap_object.dart';
import 'i_cmap_location.dart';

class CMapParser {
  static const String def = "def";
  static const String endcidrange = "endcidrange";
  static const String endcidchar = "endcidchar";
  static const String endbfrange = "endbfrange";
  static const String endbfchar = "endbfchar";
  static const String endcodespacerange = "endcodespacerange";
  static const String usecmap = "usecmap";
  static const String registry = "Registry";
  static const String ordering = "Ordering";
  static const String supplement = "Supplement";
  static const String cmapName = "CMapName";

  static const int maxLevel = 10;

  static Future<void> parseCid(
      String cmapName, AbstractCMap cmap, ICMapLocation location) async {
    await _parseCid(cmapName, cmap, location, 0);
  }

  static void parseCidSync(
      String cmapName, AbstractCMap cmap, ICMapLocation location) {
    _parseCidSync(cmapName, cmap, location, 0);
  }

  static Future<void> _parseCid(String cmapName, AbstractCMap cmap,
      ICMapLocation location, int level) async {
    if (level >= maxLevel) {
      return;
    }
    var inp = await location.getLocation(cmapName);
    try {
      List<CMapObject> list = [];
      CMapContentParser cp = CMapContentParser(inp);
      int maxExc = 50;
      while (true) {
        try {
          await cp.parse(list);
        } catch (e) {
          if (--maxExc < 0) {
            break;
          }
          continue;
        }
        if (list.isEmpty) {
          break;
        }
        String last = list.last.toString();
        if (level == 0 && list.length == 3 && last == def) {
          CMapObject obj = list[0];
          if (registry == obj.toString()) {
            cmap.setRegistry(list[1].toString());
          } else if (ordering == obj.toString()) {
            cmap.setOrdering(list[1].toString());
          } else if (cmapName == obj.toString()) {
            cmap.setName(list[1].toString());
          } else if (supplement == obj.toString()) {
            try {
              cmap.setSupplement(list[1].getValue() as int);
            } catch (e) {}
          }
        } else {
          if ((last == endcidchar || last == endbfchar) && list.length >= 3) {
            int lMax = list.length - 2;
            for (int k = 0; k < lMax; k += 2) {
              if (list[k].isString()) {
                cmap.addChar(list[k].toString(), list[k + 1]);
              }
            }
          } else if ((last == endcidrange || last == endbfrange) &&
              list.length >= 4) {
            int lMax = list.length - 3;
            for (int k = 0; k < lMax; k += 3) {
              if (list[k].isString() && list[k + 1].isString()) {
                cmap.addRange(
                    list[k].toString(), list[k + 1].toString(), list[k + 2]);
              }
            }
          } else if (last == usecmap && list.length == 2 && list[0].isName()) {
            await _parseCid(list[0].toString(), cmap, location, level + 1);
          } else if (last == endcodespacerange) {
            for (int i = 0; i < list.length - 1; i += 2) {
              if (list[i].isHexString() && list[i + 1].isHexString()) {
                var low = list[i].toHexByteArray() as Uint8List?;
                var high = list[i + 1].toHexByteArray() as Uint8List?;
                if (low != null && high != null) {
                  cmap.addCodeSpaceRange(low, high);
                }
              }
            }
          }
        }
      }
    } catch (e) {
      // Log error
    } finally {
      await inp.close();
    }
  }

  static void _parseCidSync(
      String cmapName, AbstractCMap cmap, ICMapLocation location, int level) {
    if (level >= maxLevel) {
      return;
    }
    var inp = location.getLocationSync(cmapName);
    try {
      List<CMapObject> list = [];
      CMapContentParser cp = CMapContentParser(inp);
      int maxExc = 50;
      while (true) {
        try {
          cp.parseSync(list);
        } catch (e) {
          if (--maxExc < 0) {
            break;
          }
          continue;
        }
        if (list.isEmpty) {
          break;
        }
        String last = list.last.toString();
        if (level == 0 && list.length == 3 && last == def) {
          CMapObject obj = list[0];
          if (registry == obj.toString()) {
            cmap.setRegistry(list[1].toString());
          } else if (ordering == obj.toString()) {
            cmap.setOrdering(list[1].toString());
          } else if (cmapName == obj.toString()) {
            cmap.setName(list[1].toString());
          } else if (supplement == obj.toString()) {
            try {
              cmap.setSupplement(list[1].getValue() as int);
            } catch (e) {}
          }
        } else {
          if ((last == endcidchar || last == endbfchar) && list.length >= 3) {
            int lMax = list.length - 2;
            for (int k = 0; k < lMax; k += 2) {
              if (list[k].isString()) {
                cmap.addChar(list[k].toString(), list[k + 1]);
              }
            }
          } else if ((last == endcidrange || last == endbfrange) &&
              list.length >= 4) {
            int lMax = list.length - 3;
            for (int k = 0; k < lMax; k += 3) {
              if (list[k].isString() && list[k + 1].isString()) {
                cmap.addRange(
                    list[k].toString(), list[k + 1].toString(), list[k + 2]);
              }
            }
          } else if (last == usecmap && list.length == 2 && list[0].isName()) {
            _parseCidSync(list[0].toString(), cmap, location, level + 1);
          } else if (last == endcodespacerange) {
            for (int i = 0; i < list.length - 1; i += 2) {
              if (list[i].isHexString() && list[i + 1].isHexString()) {
                var low = list[i].toHexByteArray() as Uint8List?;
                var high = list[i + 1].toHexByteArray() as Uint8List?;
                if (low != null && high != null) {
                  cmap.addCodeSpaceRange(low, high);
                }
              }
            }
          }
        }
      }
    } catch (e) {
      // Log error
    } finally {
      inp.closeSync();
    }
  }
}
