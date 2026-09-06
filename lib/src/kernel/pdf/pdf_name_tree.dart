import '../exceptions/pdf_exception.dart';
import 'pdf_object.dart';
import 'pdf_string.dart';
import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_array.dart';
import 'generic_name_tree.dart';
import 'pdf_catalog.dart';

class PdfNameTree extends GenericNameTree {
  final PdfCatalog _catalog;
  final PdfName _treeType;

  PdfNameTree(PdfCatalog catalog, PdfName treeType)
      : _catalog = catalog,
        _treeType = treeType,
        super(catalog.getPdfObject().getIndirectReference()?.getDocument() ??
            (throw PdfException("Catalog must be attached to a document")));

  /// Creates a PdfNameTree and loads it from the catalog.
  static Future<PdfNameTree> create(
      PdfCatalog catalog, PdfName treeType) async {
    final tree = PdfNameTree(catalog, treeType);
    final items = await tree._readFromCatalog();
    tree.setItems(items);
    return tree;
  }

  Future<Map<PdfString, PdfObject>> _readFromCatalog() async {
    final namesDict =
        await _catalog.getPdfObject().getAsDictionary(PdfName.names);
    final treeRoot =
        namesDict == null ? null : await namesDict.getAsDictionary(_treeType);

    Map<PdfString, PdfObject> items;
    if (treeRoot == null) {
      items = {};
    } else {
      items = await GenericNameTree.readTree(treeRoot);
    }

    if (PdfName.dests == _treeType) {
      await _normalizeDestinations(items);
      await _insertDestsEntriesFromCatalog(items);
    }

    return items;
  }

  Future<void> _normalizeDestinations(Map<PdfString, PdfObject> items) async {
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
      Map<PdfString, PdfObject> items) async {
    final destinations =
        await _catalog.getPdfObject().getAsDictionary(PdfName.dests);
    if (destinations != null) {
      final keys = destinations.getMap()?.keys.toList() ?? [];
      for (final key in keys) {
        final val = await destinations.get(key);
        final array = await _getDestArray(val);
        if (array == null) continue;
        items[PdfString(key.getValue())] = array;
      }
    }
  }

  static Future<PdfArray?> _getDestArray(PdfObject? obj) async {
    if (obj == null) return null;
    if (obj.isArray()) return obj as PdfArray;
    if (obj.isDictionary()) {
      return await (obj as PdfDictionary).getAsArray(PdfName.d); // 'D'
    }
    return null;
  }
}
