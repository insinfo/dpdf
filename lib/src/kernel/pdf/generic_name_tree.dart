import 'dart:math';

import 'pdf_object.dart';
import 'pdf_string.dart';
import 'pdf_dictionary.dart';
import 'pdf_array.dart';
import 'pdf_name.dart';
import 'pdf_document.dart';
import 'pdf_name_tree_access.dart';

/// Abstract representation of a name tree structure.
class CraftGenericNameTree implements CraftPdfNameTreeAccess {
  static const int _nodeSize = 40;

  // Use SplayTreeMap or similar if we wanted auto-sort, but keys can change.
  // We use a Map and sort when building.
  Map<CraftPdfString, CraftPdfObject> _items = {};

  final CraftPdfDocument _pdfDoc;
  bool _modified = false;

  CraftGenericNameTree(this._pdfDoc);

  /// Add an entry to the name tree.
  void addEntry(CraftPdfString key, CraftPdfObject value) {
    _addEntry(key, value, null);
  }

  /// Add an entry to the name tree.
  void addEntryString(String key, CraftPdfObject value) {
    addEntry(CraftPdfString(key), value);
  }

  /// Remove an entry from the name tree.
  void removeEntry(CraftPdfString key) {
    final existingVal = _items.remove(key);
    if (existingVal != null) {
      _modified = true;
    }
  }

  @override
  Future<CraftPdfObject?> getEntry(CraftPdfString key) async {
    return _items[key];
  }

  @override
  Future<CraftPdfObject?> getEntryAsString(String key) async {
    return await getEntry(CraftPdfString(key));
  }

  @override
  Future<List<CraftPdfString>> getKeys() async {
    return _items.keys.toList();
  }

  bool hasChanges() => _modified;

  void markChanged() {
    _modified = true;
  }

  /// Build a PdfDictionary containing the name tree.
  CraftPdfDictionary buildTree() {
    final names = _items.keys.toList();
    names.sort(_comparePdfStrings);

    if (names.length <= _nodeSize) {
      final dic = CraftPdfDictionary();
      final ar = CraftPdfArray();
      for (final name in names) {
        ar.add(name);
        final val = _items[name];
        if (val != null) {
          ar.add(val);
        }
      }
      dic.put(CraftPdfName.names, ar);
      return dic;
    }

    final leaves = _constructLeafArr(names);
    return _reduceTree(names, leaves, leaves.length, _nodeSize * _nodeSize);
  }

  void _addEntry(CraftPdfString key, CraftPdfObject value,
      Function(CraftPdfDocument)? onErrorAction) {
    final existingVal = _items[key];
    if (existingVal != null) {
      final valueRef = value.indirectHandle();
      if (valueRef != null && valueRef == existingVal.indirectHandle()) {
        return;
      } else {
        // Log warning?
        if (onErrorAction != null) {
          onErrorAction(_pdfDoc);
        }
      }
    }
    _modified = true;
    _items[key] = value;
  }

  void setItems(Map<CraftPdfString, CraftPdfObject> items) {
    _items = items;
  }

  Map<CraftPdfString, CraftPdfObject> getItems() => _items;

  /// Read the entries in a name tree structure from a dictionary.
  static Future<Map<CraftPdfString, CraftPdfObject>> readTree(
      CraftPdfDictionary? dictionary) async {
    final items = <CraftPdfString, CraftPdfObject>{};
    if (dictionary != null) {
      await _iterateItems(dictionary, items, null);
    }
    return items;
  }

  static int _comparePdfStrings(CraftPdfString a, CraftPdfString b) {
    final bytesA = a.getValueBytes();
    final bytesB = b.getValueBytes();
    if (bytesA == null && bytesB == null) return 0;
    if (bytesA == null) return -1;
    if (bytesB == null) return 1;

    final len = min(bytesA.length, bytesB.length);
    for (var i = 0; i < len; i++) {
      final diff = bytesA[i] - bytesB[i];
      if (diff != 0) return diff;
    }
    return bytesA.length - bytesB.length;
  }

  CraftPdfDictionary _formatNodeWithLimits(
      List<CraftPdfString> names, int lower, int upper) {
    final dic = CraftPdfDictionary();
    dic.attachToDocument(_pdfDoc);
    final limitsArr = CraftPdfArray();
    limitsArr.add(names[lower]);
    limitsArr.add(names[upper]);
    dic.put(CraftPdfName.limits, limitsArr);
    return dic;
  }

  CraftPdfDictionary _reduceTree(List<CraftPdfString> names,
      List<CraftPdfDictionary> topLayer, int topLayerLen, int curNodeSpan) {
    if (topLayerLen <= _nodeSize) {
      final kidsArr = CraftPdfArray();
      for (int i = 0; i < topLayerLen; ++i) {
        kidsArr.add(topLayer[i]);
      }
      final root = CraftPdfDictionary();
      root.put(CraftPdfName.kids, kidsArr);
      return root;
    }

    int nextLayerLen = (names.length + curNodeSpan - 1) ~/ curNodeSpan;

    final newTopLayer = List<CraftPdfDictionary>.filled(
        nextLayerLen, CraftPdfDictionary()); // placeholders

    for (int i = 0; i < nextLayerLen; ++i) {
      int lowerLimit = i * curNodeSpan;
      int upperLimit = min((i + 1) * curNodeSpan, names.length) - 1;
      final dic = _formatNodeWithLimits(names, lowerLimit, upperLimit);
      final kidsArr = CraftPdfArray();
      int offset = i * _nodeSize;
      int end = min(offset + _nodeSize, topLayerLen);
      for (; offset < end; ++offset) {
        kidsArr.add(topLayer[offset]);
      }
      dic.put(CraftPdfName.kids, kidsArr);
      newTopLayer[i] = dic;
    }
    return _reduceTree(
        names, newTopLayer, nextLayerLen, curNodeSpan * _nodeSize);
  }

  List<CraftPdfDictionary> _constructLeafArr(List<CraftPdfString> names) {
    final len = (names.length + _nodeSize - 1) ~/ _nodeSize;
    final leaves = <CraftPdfDictionary>[];

    for (int k = 0; k < len; ++k) {
      int offset = k * _nodeSize;
      int end = min(offset + _nodeSize, names.length);
      final dic = _formatNodeWithLimits(names, offset, end - 1);
      final namesArr = CraftPdfArray();
      for (int j = offset; j < end; ++j) {
        namesArr.add(names[j]);
        namesArr.add(_items[names[j]]!);
      }
      dic.put(CraftPdfName.names, namesArr);
      dic.attachToDocument(_pdfDoc);
      leaves.add(dic);
    }
    return leaves;
  }

  static Future<CraftPdfString?> _iterateItems(
      CraftPdfDictionary dictionary,
      Map<CraftPdfString, CraftPdfObject> items,
      CraftPdfString? leftOver) async {
    final names = await dictionary.arrayEntry(CraftPdfName.names);
    final kids = await dictionary.arrayEntry(CraftPdfName.kids);
    bool isLeafNode = names != null && names.size() > 0;
    bool isIntermNode = kids != null && kids.size() > 0;

    if (isLeafNode) {
      return await _iterateLeafNode(names, items, leftOver);
    } else {
      if (isIntermNode) {
        CraftPdfString? curLeftOver = leftOver;
        for (int k = 0; k < kids.size(); k++) {
          final kid = await kids.dictionaryEntry(k);
          if (kid != null) {
            curLeftOver = await _iterateItems(kid, items, curLeftOver);
          }
        }
        return curLeftOver;
      } else {
        return leftOver;
      }
    }
  }

  static Future<CraftPdfString?> _iterateLeafNode(
      CraftPdfArray names,
      Map<CraftPdfString, CraftPdfObject> items,
      CraftPdfString? leftOver) async {
    int k = 0;
    if (leftOver != null) {
      final val = await names.get(0);
      if (val != null) {
        items[leftOver] = val;
      }
      k++;
    }
    while (k < names.size()) {
      final name = await names.stringEntry(k);
      k++;
      if (k == names.size()) {
        return name;
      }
      if (name != null) {
        final val = await names.get(k);
        if (val != null) {
          items[name] = val;
        }
      }
      k++;
    }
    return null;
  }
}
