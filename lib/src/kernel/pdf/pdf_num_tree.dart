import 'dart:math';

import 'pdf_catalog.dart';
import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_object.dart';
import 'pdf_array.dart';
import 'pdf_number.dart';

class CraftPdfNumTree {
  static const int _nodeSize = 40;

  final CraftPdfCatalog _catalog;
  final Map<int, CraftPdfObject> _items = {};
  final CraftPdfName _treeType;

  /// Creates the NumberTree of current Document
  CraftPdfNumTree(this._catalog, this._treeType);

  Future<Map<int, CraftPdfObject>> getNumbers() async {
    if (_items.isNotEmpty) {
      return _items;
    }
    CraftPdfDictionary? numbers;
    if (_treeType == CraftPdfName.pageLabels) {
      numbers = await _catalog
          .pdfRepresentation()
          .dictionaryEntry(CraftPdfName.pageLabels);
    } else {
      if (_treeType == CraftPdfName.parentTree) {
        final structTreeRoot = await _catalog
            .pdfRepresentation()
            .dictionaryEntry(CraftPdfName.structTreeRoot);
        if (structTreeRoot != null) {
          numbers =
              await structTreeRoot.dictionaryEntry(CraftPdfName.parentTree);
        }
      }
    }

    if (numbers != null) {
      await _readTree(numbers);
    }
    return _items;
  }

  Future<CraftPdfObject?> get(int key) async {
    final numbers = await getNumbers();
    return numbers[key];
  }

  void addEntry(int key, CraftPdfObject value) {
    _items[key] = value;
  }

  Future<CraftPdfDictionary> buildTree() async {
    final numbers = _items.keys.toList()..sort();
    if (numbers.length <= _nodeSize) {
      final dic = CraftPdfDictionary();
      final ar = CraftPdfArray();
      for (final number in numbers) {
        ar.add(CraftPdfNumber.fromInt(number));
        ar.add(_items[number]!);
      }
      dic.put(CraftPdfName.nums, ar);
      return dic;
    }

    var skip = _nodeSize;
    final kids = List<CraftPdfDictionary?>.filled(
        (numbers.length + _nodeSize - 1) ~/ _nodeSize, null);

    for (var i = 0; i < kids.length; ++i) {
      var offset = i * _nodeSize;
      final end = min(offset + _nodeSize, numbers.length);
      final dic = CraftPdfDictionary();
      var arr = CraftPdfArray();
      arr.add(CraftPdfNumber.fromInt(numbers[offset]));
      arr.add(CraftPdfNumber.fromInt(numbers[end - 1]));
      dic.put(CraftPdfName.limits, arr);
      arr = CraftPdfArray();
      for (; offset < end; ++offset) {
        arr.add(CraftPdfNumber.fromInt(numbers[offset]));
        arr.add(_items[numbers[offset]]!);
      }
      dic.put(CraftPdfName.nums, arr);
      dic.attachToDocument(_catalog.getDocument()!);
      kids[i] = dic;
    }

    var top = kids.length;
    while (true) {
      if (top <= _nodeSize) {
        final arr = CraftPdfArray();
        for (var k = 0; k < top; ++k) {
          if (kids[k] != null) {
            arr.add(kids[k]!);
          }
        }
        final dic = CraftPdfDictionary();
        dic.put(CraftPdfName.kids, arr);
        return dic;
      }
      skip *= _nodeSize;
      final tt = (numbers.length + skip - 1) ~/ skip;
      for (var k = 0; k < tt; ++k) {
        var offset = k * _nodeSize;
        final end = min(offset + _nodeSize, top);
        final dic = CraftPdfDictionary();
        dic.attachToDocument(_catalog.getDocument()!);
        var arr = CraftPdfArray();
        arr.add(CraftPdfNumber.fromInt(numbers[k * skip]));
        arr.add(CraftPdfNumber.fromInt(
            numbers[min((k + 1) * skip, numbers.length) - 1]));
        dic.put(CraftPdfName.limits, arr);
        arr = CraftPdfArray();
        for (; offset < end; ++offset) {
          if (kids[offset] != null) {
            arr.add(kids[offset]!);
          }
        }
        dic.put(CraftPdfName.kids, arr);
        kids[k] = dic;
      }
      top = tt;
    }
  }

  Future<void> _readTree(CraftPdfDictionary dictionary) async {
    await _iterateItems(dictionary, null);
  }

  Future<CraftPdfNumber?> _iterateItems(
      CraftPdfDictionary dictionary, CraftPdfNumber? leftOver) async {
    var nums = await dictionary.arrayEntry(CraftPdfName.nums);
    if (nums != null) {
      for (var k = 0; k < nums.size(); k++) {
        CraftPdfNumber? number;
        if (leftOver == null) {
          number = await nums.numberEntry(k++);
        } else {
          number = leftOver;
          leftOver = null;
        }

        if (number != null) {
          if (k < nums.size()) {
            final val = await nums.get(k);
            if (val != null) {
              _items[number.intValue()] = val;
            }
          } else {
            return number;
          }
        }
      }
    } else {
      final kids = await dictionary.arrayEntry(CraftPdfName.kids);
      if (kids != null) {
        for (var k = 0; k < kids.size(); k++) {
          final kid = await kids.dictionaryEntry(k);
          if (kid != null) {
            leftOver = await _iterateItems(kid, leftOver);
          }
        }
      }
    }
    return null;
  }
}
