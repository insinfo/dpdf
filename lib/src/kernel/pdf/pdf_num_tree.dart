import 'dart:math';

import 'pdf_catalog.dart';
import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_object.dart';
import 'pdf_array.dart';
import 'pdf_number.dart';

class PdfNumTree {
  static const int _nodeSize = 40;

  final PdfCatalog _catalog;
  final Map<int, PdfObject> _items = {};
  final PdfName _treeType;

  /// Creates the NumberTree of current Document
  PdfNumTree(this._catalog, this._treeType);

  Future<Map<int, PdfObject>> getNumbers() async {
    if (_items.isNotEmpty) {
      return _items;
    }
    PdfDictionary? numbers;
    if (_treeType == PdfName.pageLabels) {
      numbers = await _catalog.getPdfObject().getAsDictionary(PdfName.pageLabels);
    } else {
      if (_treeType == PdfName.parentTree) {
        final structTreeRoot =
            await _catalog.getPdfObject().getAsDictionary(PdfName.structTreeRoot);
        if (structTreeRoot != null) {
          numbers = await structTreeRoot.getAsDictionary(PdfName.parentTree);
        }
      }
    }

    if (numbers != null) {
      await _readTree(numbers);
    }
    return _items;
  }

  Future<PdfObject?> get(int key) async {
    final numbers = await getNumbers();
    return numbers[key];
  }

  void addEntry(int key, PdfObject value) {
    _items[key] = value;
  }

  Future<PdfDictionary> buildTree() async {
    final numbers = _items.keys.toList()..sort();
    if (numbers.length <= _nodeSize) {
      final dic = PdfDictionary();
      final ar = PdfArray();
      for (final number in numbers) {
        ar.add(PdfNumber.fromInt(number));
        ar.add(_items[number]!);
      }
      dic.put(PdfName.nums, ar);
      return dic;
    }

    var skip = _nodeSize;
    final kids =
        List<PdfDictionary?>.filled((numbers.length + _nodeSize - 1) ~/ _nodeSize, null);

    for (var i = 0; i < kids.length; ++i) {
      var offset = i * _nodeSize;
      final end = min(offset + _nodeSize, numbers.length);
      final dic = PdfDictionary();
      var arr = PdfArray();
      arr.add(PdfNumber.fromInt(numbers[offset]));
      arr.add(PdfNumber.fromInt(numbers[end - 1]));
      dic.put(PdfName.limits, arr);
      arr = PdfArray();
      for (; offset < end; ++offset) {
        arr.add(PdfNumber.fromInt(numbers[offset]));
        arr.add(_items[numbers[offset]]!);
      }
      dic.put(PdfName.nums, arr);
      dic.makeIndirect(_catalog.getDocument()!);
      kids[i] = dic;
    }

    var top = kids.length;
    while (true) {
      if (top <= _nodeSize) {
        final arr = PdfArray();
        for (var k = 0; k < top; ++k) {
          if (kids[k] != null) {
            arr.add(kids[k]!);
          }
        }
        final dic = PdfDictionary();
        dic.put(PdfName.kids, arr);
        return dic;
      }
      skip *= _nodeSize;
      final tt = (numbers.length + skip - 1) ~/ skip;
      for (var k = 0; k < tt; ++k) {
        var offset = k * _nodeSize;
        final end = min(offset + _nodeSize, top);
        final dic = PdfDictionary();
        dic.makeIndirect(_catalog.getDocument()!);
        var arr = PdfArray();
        arr.add(PdfNumber.fromInt(numbers[k * skip]));
        arr.add(PdfNumber.fromInt(numbers[min((k + 1) * skip, numbers.length) - 1]));
        dic.put(PdfName.limits, arr);
        arr = PdfArray();
        for (; offset < end; ++offset) {
          if (kids[offset] != null) {
            arr.add(kids[offset]!);
          }
        }
        dic.put(PdfName.kids, arr);
        kids[k] = dic;
      }
      top = tt;
    }
  }

  Future<void> _readTree(PdfDictionary dictionary) async {
    await _iterateItems(dictionary, null);
  }

  Future<PdfNumber?> _iterateItems(
      PdfDictionary dictionary, PdfNumber? leftOver) async {
    var nums = await dictionary.getAsArray(PdfName.nums);
    if (nums != null) {
      for (var k = 0; k < nums.size(); k++) {
        PdfNumber? number;
        if (leftOver == null) {
          number = await nums.getAsNumber(k++);
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
      final kids = await dictionary.getAsArray(PdfName.kids);
      if (kids != null) {
        for (var k = 0; k < kids.size(); k++) {
          final kid = await kids.getAsDictionary(k);
          if (kid != null) {
            leftOver = await _iterateItems(kid, leftOver);
          }
        }
      }
    }
    return null;
  }
}