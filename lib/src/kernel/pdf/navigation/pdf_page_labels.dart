import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_string.dart';

/// Page label dictionary.
///
/// See ISO 32000-1:2008, 12.4.2 "Page Labels", Table 159.
class PdfPageLabel {
  /// `/S /D`: decimal arabic numerals.
  static final PdfName decimal = PdfName.intern('D');

  /// `/S /R`: uppercase roman numerals.
  static final PdfName uppercaseRoman = PdfName.intern('R');

  /// `/S /r`: lowercase roman numerals.
  static final PdfName lowercaseRoman = PdfName.intern('r');

  /// `/S /A`: uppercase letters.
  static final PdfName uppercaseLetters = PdfName.intern('A');

  /// `/S /a`: lowercase letters.
  static final PdfName lowercaseLetters = PdfName.intern('a');

  static final Set<String> _styles = {
    decimal.getValue(),
    uppercaseRoman.getValue(),
    lowercaseRoman.getValue(),
    uppercaseLetters.getValue(),
    lowercaseLetters.getValue(),
  };

  /// The numbering style, or null when the range has no numeric portion.
  final PdfName? style;

  /// The label prefix, or null when the range has none.
  final String? prefix;

  /// The value of the numeric portion of the first label in the range.
  /// Table 159 requires a value greater than or equal to 1; the default is 1.
  final int start;

  PdfPageLabel({this.style, this.prefix, this.start = 1}) {
    if (style != null && !_styles.contains(style!.getValue())) {
      throw ArgumentError.value(style, 'style',
          'Page label /S shall be /D, /R, /r, /A or /a (Table 159)');
    }
    if (start < 1) {
      throw ArgumentError.value(
          start, 'start', 'Page label /St shall be greater than or equal to 1');
    }
  }

  /// Builds the page label dictionary, writing `/Type /PageLabel` and only
  /// the entries that differ from the defaults of Table 159.
  PdfDictionary toDictionary() {
    final dictionary = PdfDictionary();
    dictionary.put(PdfName.type, PdfName.intern('PageLabel'));
    if (style != null) dictionary.put(PdfName.s, style!);
    if (prefix != null) dictionary.put(PdfName.p, PdfString(prefix!));
    if (start != 1) dictionary.put(PdfName.st, PdfNumber.fromInt(start));
    return dictionary;
  }

  /// Reads a page label dictionary.
  static Future<PdfPageLabel> fromDictionary(PdfDictionary dictionary) async {
    return PdfPageLabel(
      style: await dictionary.nameEntry(PdfName.s),
      prefix: (await dictionary.stringEntry(PdfName.p))?.decodeMappingText(),
      start: await dictionary.integerEntry(PdfName.st) ?? 1,
    );
  }

  /// Formats the label of the page whose offset inside the labelling range is
  /// [offsetInRange] (zero based), following 12.4.2.
  String format(int offsetInRange) {
    if (offsetInRange < 0) {
      throw ArgumentError.value(offsetInRange, 'offsetInRange',
          'Offsets inside a labelling range are zero based');
    }
    final buffer = StringBuffer(prefix ?? '');
    final style = this.style;
    if (style != null) {
      final number = start + offsetInRange;
      final value = style.getValue();
      switch (value) {
        case 'D':
          buffer.write('$number');
          break;
        case 'R':
          buffer.write(_roman(number).toUpperCase());
          break;
        case 'r':
          buffer.write(_roman(number));
          break;
        case 'A':
          buffer.write(_letters(number).toUpperCase());
          break;
        case 'a':
          buffer.write(_letters(number));
          break;
      }
    }
    return buffer.toString();
  }

  static const List<int> _romanValues = [
    1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 //
  ];
  static const List<String> _romanLiterals = [
    'm', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v', 'iv', 'i' //
  ];

  static String _roman(int number) {
    if (number <= 0) return '';
    final buffer = StringBuffer();
    var remaining = number;
    for (var i = 0; i < _romanValues.length; i++) {
      while (remaining >= _romanValues[i]) {
        buffer.write(_romanLiterals[i]);
        remaining -= _romanValues[i];
      }
    }
    return buffer.toString();
  }

  /// A to Z for the first 26 pages, AA to ZZ for the next 26, and so on
  /// (Table 159).
  static String _letters(int number) {
    if (number <= 0) return '';
    final index = (number - 1) % 26;
    final repeat = ((number - 1) ~/ 26) + 1;
    return String.fromCharCode(0x61 + index) * repeat;
  }
}

/// The `/PageLabels` number tree of the document catalog.
///
/// See ISO 32000-1:2008, 12.4.2. The tree maps the page index of the first
/// page of a labelling range to its page label dictionary and shall include a
/// value for page index 0.
class PdfPageLabelTree {
  final Map<int, PdfPageLabel> _ranges = {};

  /// Registers the labelling range starting at [pageIndex] (zero based).
  void setRange(int pageIndex, PdfPageLabel label) {
    if (pageIndex < 0) {
      throw ArgumentError.value(
          pageIndex, 'pageIndex', 'Page indices are zero based');
    }
    _ranges[pageIndex] = label;
  }

  /// The registered ranges, ordered by their first page index.
  Map<int, PdfPageLabel> get ranges => Map.fromEntries(
      _ranges.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));

  /// Builds the `/PageLabels` number tree dictionary.
  ///
  /// Throws when no range starts at page index 0, which 12.4.2 requires.
  PdfDictionary toDictionary() {
    if (!_ranges.containsKey(0)) {
      throw StateError(
          'The /PageLabels number tree shall include a value for page index 0');
    }
    final nums = PdfArray();
    for (final entry in ranges.entries) {
      nums.add(PdfNumber.fromInt(entry.key));
      nums.add(entry.value.toDictionary());
    }
    final tree = PdfDictionary();
    tree.put(PdfName.nums, nums);
    return tree;
  }

  /// Reads a `/PageLabels` number tree, accepting both the flat `/Nums` form
  /// and the `/Kids` form of 7.9.7 "Number Trees".
  static Future<PdfPageLabelTree> fromDictionary(PdfDictionary tree) async {
    final result = PdfPageLabelTree();
    await _read(tree, result);
    return result;
  }

  static Future<void> _read(PdfDictionary node, PdfPageLabelTree into) async {
    final nums = await node.arrayEntry(PdfName.nums);
    if (nums != null) {
      for (var i = 0; i + 1 < nums.size(); i += 2) {
        final key = await nums.get(i);
        final value = await nums.get(i + 1, true);
        if (key is PdfNumber && value is PdfDictionary) {
          into.setRange(
              key.intValue(), await PdfPageLabel.fromDictionary(value));
        }
      }
    }
    final kids = await node.arrayEntry(PdfName.kids);
    if (kids != null) {
      for (var i = 0; i < kids.size(); i++) {
        final kid = await kids.get(i, true);
        if (kid is PdfDictionary) await _read(kid, into);
      }
    }
  }

  /// Returns the label of the page at [pageIndex] (zero based), or null when
  /// no range covers it.
  String? labelAt(int pageIndex) {
    int? rangeStart;
    for (final start in _ranges.keys) {
      if (start <= pageIndex && (rangeStart == null || start > rangeStart)) {
        rangeStart = start;
      }
    }
    if (rangeStart == null) return null;
    return _ranges[rangeStart]!.format(pageIndex - rangeStart);
  }

  /// Returns the labels of the first [pageCount] pages.
  List<String?> labels(int pageCount) =>
      [for (var i = 0; i < pageCount; i++) labelAt(i)];
}

/// Reads the `/PageLabels` entry of a document catalog dictionary.
Future<PdfPageLabelTree?> readPageLabels(PdfDictionary catalog) async {
  final tree = await catalog.dictionaryEntry(PdfName.pageLabels);
  if (tree == null) return null;
  return await PdfPageLabelTree.fromDictionary(tree);
}

/// Writes [labels] into the `/PageLabels` entry of a document catalog.
void writePageLabels(PdfDictionary catalog, PdfPageLabelTree labels) {
  catalog.put(PdfName.pageLabels, labels.toDictionary());
}
