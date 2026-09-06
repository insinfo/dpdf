import 'dart:math';

import 'pdf_object.dart';
import 'pdf_string.dart';
import 'pdf_dictionary.dart';
import 'pdf_array.dart';
import 'pdf_name.dart';
import 'pdf_document.dart';
import 'i_pdf_name_tree_access.dart';

/// Abstract representation of a name tree structure.
class GenericNameTree implements IPdfNameTreeAccess {
  static const int _nodeSize = 40;

  // Use SplayTreeMap or similar if we wanted auto-sort, but keys can change.
  // We use a Map and sort when building.
  Map<PdfString, PdfObject> _items = {};

  final PdfDocument _pdfDoc;
  bool _modified = false;

  GenericNameTree(this._pdfDoc);

  /// Add an entry to the name tree.
  void addEntry(PdfString key, PdfObject value) {
    _addEntry(key, value, null);
  }

  /// Add an entry to the name tree.
  void addEntryString(String key, PdfObject value) {
    addEntry(PdfString(key), value);
  }

  /// Remove an entry from the name tree.
  void removeEntry(PdfString key) {
    final existingVal = _items.remove(key);
    if (existingVal != null) {
      _modified = true;
    }
  }

  @override
  Future<PdfObject?> getEntry(PdfString key) async {
    return _items[key];
  }

  @override
  Future<PdfObject?> getEntryAsString(String key) async {
    return await getEntry(PdfString(key));
  }

  @override
  Future<List<PdfString>> getKeys() async {
    return _items.keys.toList();
  }

  bool isModified() => _modified;

  void setModified() {
    _modified = true;
  }

  /// Build a PdfDictionary containing the name tree.
  PdfDictionary buildTree() {
    final names = _items.keys.toList();
    names.sort(_comparePdfStrings);

    if (names.length <= _nodeSize) {
      final dic = PdfDictionary();
      final ar = PdfArray();
      for (final name in names) {
        ar.add(name);
        final val = _items[name];
        if (val != null) {
          ar.add(val);
        }
      }
      dic.put(PdfName.names, ar);
      return dic;
    }

    final leaves = _constructLeafArr(names);
    return _reduceTree(names, leaves, leaves.length, _nodeSize * _nodeSize);
  }

  void _addEntry(
      PdfString key, PdfObject value, Function(PdfDocument)? onErrorAction) {
    final existingVal = _items[key];
    if (existingVal != null) {
      final valueRef = value.getIndirectReference();
      if (valueRef != null && valueRef == existingVal.getIndirectReference()) {
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

  void setItems(Map<PdfString, PdfObject> items) {
    _items = items;
  }

  Map<PdfString, PdfObject> getItems() => _items;

  /// Read the entries in a name tree structure from a dictionary.
  static Future<Map<PdfString, PdfObject>> readTree(
      PdfDictionary? dictionary) async {
    final items = <PdfString, PdfObject>{};
    if (dictionary != null) {
      await _iterateItems(dictionary, items, null);
    }
    return items;
  }

  static int _comparePdfStrings(PdfString a, PdfString b) {
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

  PdfDictionary _formatNodeWithLimits(
      List<PdfString> names, int lower, int upper) {
    final dic = PdfDictionary();
    dic.makeIndirect(_pdfDoc);
    final limitsArr = PdfArray();
    limitsArr.add(names[lower]);
    limitsArr.add(names[upper]);
    dic.put(PdfName.limits, limitsArr);
    return dic;
  }

  PdfDictionary _reduceTree(List<PdfString> names, List<PdfDictionary> topLayer,
      int topLayerLen, int curNodeSpan) {
    if (topLayerLen <= _nodeSize) {
      final kidsArr = PdfArray();
      for (int i = 0; i < topLayerLen; ++i) {
        kidsArr.add(topLayer[i]);
      }
      final root = PdfDictionary();
      root.put(PdfName.kids, kidsArr);
      return root;
    }

    int nextLayerLen = (names.length + curNodeSpan - 1) ~/ curNodeSpan;

    final newTopLayer = List<PdfDictionary>.filled(
        nextLayerLen, PdfDictionary()); // placeholders

    for (int i = 0; i < nextLayerLen; ++i) {
      int lowerLimit = i * curNodeSpan;
      int upperLimit = min((i + 1) * curNodeSpan, names.length) - 1;
      final dic = _formatNodeWithLimits(names, lowerLimit, upperLimit);
      final kidsArr = PdfArray();
      int offset = i * _nodeSize;
      int end = min(offset + _nodeSize, topLayerLen);
      for (; offset < end; ++offset) {
        kidsArr.add(topLayer[offset]);
      }
      dic.put(PdfName.kids, kidsArr);
      newTopLayer[i] = dic;
    }
    return _reduceTree(
        names, newTopLayer, nextLayerLen, curNodeSpan * _nodeSize);
  }

  List<PdfDictionary> _constructLeafArr(List<PdfString> names) {
    final len = (names.length + _nodeSize - 1) ~/ _nodeSize;
    final leaves = <PdfDictionary>[];

    for (int k = 0; k < len; ++k) {
      int offset = k * _nodeSize;
      int end = min(offset + _nodeSize, names.length);
      final dic = _formatNodeWithLimits(names, offset, end - 1);
      final namesArr = PdfArray();
      for (int j = offset; j < end; ++j) {
        namesArr.add(names[j]);
        namesArr.add(_items[names[j]]!);
      }
      dic.put(PdfName.names, namesArr);
      dic.makeIndirect(_pdfDoc);
      leaves.add(dic);
    }
    return leaves;
  }

  static Future<PdfString?> _iterateItems(PdfDictionary dictionary,
      Map<PdfString, PdfObject> items, PdfString? leftOver) async {
    final names = await dictionary.getAsArray(PdfName.names);
    final kids = await dictionary.getAsArray(PdfName.kids);
    bool isLeafNode = names != null && names.size() > 0;
    bool isIntermNode = kids != null && kids.size() > 0;

    if (isLeafNode) {
      return await _iterateLeafNode(names, items, leftOver);
    } else {
      if (isIntermNode) {
        PdfString? curLeftOver = leftOver;
        for (int k = 0; k < kids.size(); k++) {
          final kid = await kids.getAsDictionary(k);
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

  static Future<PdfString?> _iterateLeafNode(PdfArray names,
      Map<PdfString, PdfObject> items, PdfString? leftOver) async {
    int k = 0;
    if (leftOver != null) {
      final val = await names.get(0);
      if (val != null) {
        items[leftOver] = val;
      }
      k++;
    }
    while (k < names.size()) {
      final name = await names.getAsString(k);
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
