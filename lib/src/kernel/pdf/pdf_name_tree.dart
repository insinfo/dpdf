import '../exceptions/pdf_exception.dart';
import 'pdf_object.dart';
import 'pdf_string.dart';
import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_array.dart';
import 'generic_name_tree.dart';
import 'pdf_catalog.dart';

class CraftPdfNameTree extends CraftGenericNameTree {
  final CraftPdfCatalog _catalog;
  final CraftPdfName _treeType;

  CraftPdfNameTree(CraftPdfCatalog catalog, CraftPdfName treeType)
      : _catalog = catalog,
        _treeType = treeType,
        super(catalog.pdfRepresentation().indirectHandle()?.getDocument() ??
            (throw CraftPdfException(
                "Catalog must be attached to a document")));

  /// Creates a PdfNameTree and loads it from the catalog.
  static Future<CraftPdfNameTree> create(
      CraftPdfCatalog catalog, CraftPdfName treeType) async {
    final tree = CraftPdfNameTree(catalog, treeType);
    final items = await tree._readFromCatalog();
    tree.setItems(items);
    return tree;
  }

  Future<Map<CraftPdfString, CraftPdfObject>> _readFromCatalog() async {
    final namesDict =
        await _catalog.pdfRepresentation().dictionaryEntry(CraftPdfName.names);
    final treeRoot =
        namesDict == null ? null : await namesDict.dictionaryEntry(_treeType);

    Map<CraftPdfString, CraftPdfObject> items;
    if (treeRoot == null) {
      items = {};
    } else {
      items = await CraftGenericNameTree.readTree(treeRoot);
    }

    if (CraftPdfName.dests == _treeType) {
      await _normalizeDestinations(items);
      await _insertDestsEntriesFromCatalog(items);
    }

    return items;
  }

  Future<void> _normalizeDestinations(
      Map<CraftPdfString, CraftPdfObject> items) async {
    final keys = items.keys.toList();
    for (final key in keys) {
      final arr = await _getDestArray(items[key]);
      if (arr == null) {
        items.remove(key);
      } else {
        items[key] = arr;
      }
    }
  }

  Future<void> _insertDestsEntriesFromCatalog(
      Map<CraftPdfString, CraftPdfObject> items) async {
    final destinations =
        await _catalog.pdfRepresentation().dictionaryEntry(CraftPdfName.dests);
    if (destinations != null) {
      final keys = destinations.getMap()?.keys.toList() ?? [];
      for (final key in keys) {
        final val = await destinations.get(key);
        final array = await _getDestArray(val);
        if (array == null) continue;
        items[CraftPdfString(key.getValue())] = array;
      }
    }
  }

  static Future<CraftPdfArray?> _getDestArray(CraftPdfObject? obj) async {
    if (obj == null) return null;
    if (obj.isArray()) return obj as CraftPdfArray;
    if (obj.isDictionary()) {
      return await (obj as CraftPdfDictionary)
          .arrayEntry(CraftPdfName.d); // 'D'
    }
    return null;
  }
}
