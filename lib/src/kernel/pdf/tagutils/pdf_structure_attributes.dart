import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';
import 'standard_attribute_owners.dart';

/// An attribute object attached to a structure element
/// (ISO 32000-1:2008, 14.7.5 and 14.8.5).
///
/// Every attribute object names its owner in /O (Table 327); the owner decides
/// how the remaining entries are read. The typed setters below cover the
/// layout attributes of Tables 342-346, the list attribute of Table 347, the
/// PrintField attributes of Table 348 and the table attributes of Table 349;
/// [put] remains available for attributes this class does not name.
class PdfStructureAttributes extends PdfObjectWrapper<PdfDictionary> {
  PdfStructureAttributes(super.dictionary);

  /// Creates an attribute object owned by [owner].
  PdfStructureAttributes.withOwner(String owner) : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName('O'), PdfName(owner));
  }

  /// Creates an attribute object owned by /Layout.
  PdfStructureAttributes.layout()
      : this.withOwner(StandardAttributeOwners.layout);

  /// Creates an attribute object owned by /List.
  PdfStructureAttributes.list() : this.withOwner(StandardAttributeOwners.list);

  /// Creates an attribute object owned by /PrintField.
  PdfStructureAttributes.printField()
      : this.withOwner(StandardAttributeOwners.printField);

  /// Creates an attribute object owned by /Table.
  PdfStructureAttributes.table()
      : this.withOwner(StandardAttributeOwners.table);

  /// The name in the required /O entry.
  Future<String?> getOwner() async {
    return (await pdfRepresentation().nameEntry(PdfName('O')))?.getValue();
  }

  /// Reads back a single attribute.
  Future<PdfObject?> getAttribute(String name) async {
    return await pdfRepresentation().get(PdfName(name), true);
  }

  /// Writes an arbitrary attribute.
  PdfStructureAttributes put(PdfName key, PdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
    return this;
  }

  PdfStructureAttributes _putName(String key, String value) =>
      put(PdfName(key), PdfName(value));

  PdfStructureAttributes _putNumber(String key, double value) =>
      put(PdfName(key), PdfNumber(value));

  PdfStructureAttributes _putInt(String key, int value) =>
      put(PdfName(key), PdfNumber.fromInt(value));

  PdfStructureAttributes _putNumbers(String key, List<double> values) {
    final array = PdfArray();
    for (final value in values) {
      array.add(PdfNumber(value));
    }
    return put(PdfName(key), array);
  }

  PdfStructureAttributes _putNameOrNames(String key, List<String> values) {
    if (values.length == 1) return _putName(key, values.first);
    final array = PdfArray();
    for (final value in values) {
      array.add(PdfName(value));
    }
    return put(PdfName(key), array);
  }

  // ------------------------------------------------- layout attributes (343)

  /// Table 343 /Placement: Block, Inline, Before, Start or End.
  PdfStructureAttributes setPlacement(String placement) {
    _expect('Placement', placement, placements);
    return _putName('Placement', placement);
  }

  /// The values Table 343 allows for /Placement.
  static const Set<String> placements = {
    'Block',
    'Inline',
    'Before',
    'Start',
    'End'
  };

  /// Table 343 /WritingMode: LrTb, RlTb or TbRl.
  PdfStructureAttributes setWritingMode(String writingMode) {
    _expect('WritingMode', writingMode, writingModes);
    return _putName('WritingMode', writingMode);
  }

  /// The values Table 343 allows for /WritingMode.
  static const Set<String> writingModes = {'LrTb', 'RlTb', 'TbRl'};

  /// Table 343 /BackgroundColor, as an RGB triple in the range 0.0 to 1.0.
  PdfStructureAttributes setBackgroundColor(List<double> rgb) =>
      _putNumbers('BackgroundColor', _rgb(rgb));

  /// Table 343 /BorderColor.
  PdfStructureAttributes setBorderColor(List<double> rgb) =>
      _putNumbers('BorderColor', _rgb(rgb));

  /// Table 343 /BorderStyle, one name or one per edge.
  PdfStructureAttributes setBorderStyle(List<String> styles) {
    for (final style in styles) {
      _expect('BorderStyle', style, borderStyles);
    }
    return _putNameOrNames('BorderStyle', styles);
  }

  /// The values Table 343 allows for /BorderStyle and /TBorderStyle.
  static const Set<String> borderStyles = {
    'None',
    'Hidden',
    'Dotted',
    'Dashed',
    'Solid',
    'Double',
    'Groove',
    'Ridge',
    'Inset',
    'Outset'
  };

  /// Table 343 /BorderThickness, one number or one per edge.
  PdfStructureAttributes setBorderThickness(List<double> thickness) =>
      thickness.length == 1
          ? _putNumber('BorderThickness', thickness.first)
          : _putNumbers('BorderThickness', thickness);

  /// Table 343 /Color, the colour of text and border decorations.
  PdfStructureAttributes setColor(List<double> rgb) =>
      _putNumbers('Color', _rgb(rgb));

  /// Table 343 /Padding, one number or one per edge.
  PdfStructureAttributes setPadding(List<double> padding) =>
      padding.length == 1
          ? _putNumber('Padding', padding.first)
          : _putNumbers('Padding', padding);

  // --------------------------------------------- BLSE layout attributes (344)

  /// Table 344 /SpaceBefore.
  PdfStructureAttributes setSpaceBefore(double value) =>
      _putNumber('SpaceBefore', value);

  /// Table 344 /SpaceAfter.
  PdfStructureAttributes setSpaceAfter(double value) =>
      _putNumber('SpaceAfter', value);

  /// Table 344 /StartIndent.
  PdfStructureAttributes setStartIndent(double value) =>
      _putNumber('StartIndent', value);

  /// Table 344 /EndIndent.
  PdfStructureAttributes setEndIndent(double value) =>
      _putNumber('EndIndent', value);

  /// Table 344 /TextIndent.
  PdfStructureAttributes setTextIndent(double value) =>
      _putNumber('TextIndent', value);

  /// Table 344 /TextAlign: Start, Center, End or Justify.
  PdfStructureAttributes setTextAlign(String value) {
    _expect('TextAlign', value, textAlignments);
    return _putName('TextAlign', value);
  }

  /// The values Table 344 allows for /TextAlign.
  static const Set<String> textAlignments = {
    'Start',
    'Center',
    'End',
    'Justify'
  };

  /// Table 344 /BBox, the bounding box of an illustration element.
  PdfStructureAttributes setBBox(List<double> box) {
    if (box.length != 4) {
      throw ArgumentError.value(box, 'box', '/BBox needs four numbers.');
    }
    return _putNumbers('BBox', box);
  }

  /// Table 344 /Width, a number or the name Auto.
  PdfStructureAttributes setWidth(double value) => _putNumber('Width', value);

  /// Sets /Width to the name Auto.
  PdfStructureAttributes setAutoWidth() => _putName('Width', 'Auto');

  /// Table 344 /Height, a number or the name Auto.
  PdfStructureAttributes setHeight(double value) => _putNumber('Height', value);

  /// Sets /Height to the name Auto.
  PdfStructureAttributes setAutoHeight() => _putName('Height', 'Auto');

  /// Table 344 /BlockAlign: Before, Middle, After or Justify.
  PdfStructureAttributes setBlockAlign(String value) {
    _expect('BlockAlign', value, blockAlignments);
    return _putName('BlockAlign', value);
  }

  /// The values Table 344 allows for /BlockAlign.
  static const Set<String> blockAlignments = {
    'Before',
    'Middle',
    'After',
    'Justify'
  };

  /// Table 344 /InlineAlign: Start, Center or End.
  PdfStructureAttributes setInlineAlign(String value) {
    _expect('InlineAlign', value, inlineAlignments);
    return _putName('InlineAlign', value);
  }

  /// The values Table 344 allows for /InlineAlign.
  static const Set<String> inlineAlignments = {'Start', 'Center', 'End'};

  /// Table 344 /TBorderStyle, the border style of table cells.
  PdfStructureAttributes setTableBorderStyle(List<String> styles) {
    for (final style in styles) {
      _expect('TBorderStyle', style, borderStyles);
    }
    return _putNameOrNames('TBorderStyle', styles);
  }

  /// Table 344 /TPadding, the padding of table cells.
  PdfStructureAttributes setTablePadding(List<double> padding) =>
      padding.length == 1
          ? _putNumber('TPadding', padding.first)
          : _putNumbers('TPadding', padding);

  /// Table 345 /LineHeight, a number or the names Normal or Auto.
  PdfStructureAttributes setLineHeight(double value) =>
      _putNumber('LineHeight', value);

  /// Sets /LineHeight to one of the names Normal or Auto.
  PdfStructureAttributes setLineHeightName(String value) {
    _expect('LineHeight', value, {'Normal', 'Auto'});
    return _putName('LineHeight', value);
  }

  /// Table 345 /BaselineShift.
  PdfStructureAttributes setBaselineShift(double value) =>
      _putNumber('BaselineShift', value);

  /// Table 345 /TextDecorationType: None, Underline, Overline or LineThrough.
  PdfStructureAttributes setTextDecorationType(String value) {
    _expect('TextDecorationType', value, textDecorationTypes);
    return _putName('TextDecorationType', value);
  }

  /// The values Table 345 allows for /TextDecorationType.
  static const Set<String> textDecorationTypes = {
    'None',
    'Underline',
    'Overline',
    'LineThrough'
  };

  /// Table 345 /TextDecorationColor.
  PdfStructureAttributes setTextDecorationColor(List<double> rgb) =>
      _putNumbers('TextDecorationColor', _rgb(rgb));

  /// Table 345 /TextDecorationThickness.
  PdfStructureAttributes setTextDecorationThickness(double value) =>
      _putNumber('TextDecorationThickness', value);

  /// Table 345 /GlyphOrientationVertical, in degrees.
  PdfStructureAttributes setGlyphOrientationVertical(String value) =>
      _putName('GlyphOrientationVertical', value);

  /// Table 345 /RubyAlign: Start, Center, End, Justify or Distribute.
  PdfStructureAttributes setRubyAlign(String value) {
    _expect('RubyAlign', value, rubyAlignments);
    return _putName('RubyAlign', value);
  }

  /// The values Table 345 allows for /RubyAlign.
  static const Set<String> rubyAlignments = {
    'Start',
    'Center',
    'End',
    'Justify',
    'Distribute'
  };

  /// Table 345 /RubyPosition: Before, After, Warichu or Inline.
  PdfStructureAttributes setRubyPosition(String value) {
    _expect('RubyPosition', value, rubyPositions);
    return _putName('RubyPosition', value);
  }

  /// The values Table 345 allows for /RubyPosition.
  static const Set<String> rubyPositions = {
    'Before',
    'After',
    'Warichu',
    'Inline'
  };

  // ------------------------------------------- column attributes (Table 346)

  /// Table 346 /ColumnCount.
  PdfStructureAttributes setColumnCount(int count) {
    if (count < 1) {
      throw ArgumentError.value(count, 'count', '/ColumnCount must be at '
          'least 1.');
    }
    return _putInt('ColumnCount', count);
  }

  /// Table 346 /ColumnWidths.
  PdfStructureAttributes setColumnWidths(List<double> widths) =>
      _putNumbers('ColumnWidths', widths);

  /// Table 346 /ColumnGap.
  PdfStructureAttributes setColumnGaps(List<double> gaps) =>
      gaps.length == 1
          ? _putNumber('ColumnGap', gaps.first)
          : _putNumbers('ColumnGap', gaps);

  // ---------------------------------------------- list attribute (Table 347)

  /// Table 347 /ListNumbering, which belongs on an /L element.
  PdfStructureAttributes setListNumbering(String value) {
    _expect('ListNumbering', value, listNumberings);
    return _putName('ListNumbering', value);
  }

  /// The values Table 347 allows for /ListNumbering.
  static const Set<String> listNumberings = {
    'None',
    'Disc',
    'Circle',
    'Square',
    'Decimal',
    'UpperRoman',
    'LowerRoman',
    'UpperAlpha',
    'LowerAlpha'
  };

  // --------------------------------------- PrintField attributes (Table 348)

  /// Table 348 /Role: rb, cb, pb or tv.
  PdfStructureAttributes setPrintFieldRole(String value) {
    _expect('Role', value, printFieldRoles);
    return _putName('Role', value);
  }

  /// The values Table 348 allows for the PrintField /Role.
  static const Set<String> printFieldRoles = {'rb', 'cb', 'pb', 'tv'};

  /// Table 348 /checked: on, off or neutral. The lowercase key is the one the
  /// specification uses.
  PdfStructureAttributes setChecked(String value) {
    _expect('checked', value, checkedStates);
    return _putName('checked', value);
  }

  /// The values Table 348 allows for /checked.
  static const Set<String> checkedStates = {'on', 'off', 'neutral'};

  /// Table 348 /Desc, the alternate name of a print form field.
  PdfStructureAttributes setDescription(String value) =>
      put(PdfName('Desc'), PdfString(value));

  // -------------------------------------------- table attributes (Table 349)

  /// Table 349 /RowSpan.
  PdfStructureAttributes setRowSpan(int rows) {
    if (rows < 1) {
      throw ArgumentError.value(rows, 'rows', '/RowSpan must be at least 1.');
    }
    return _putInt('RowSpan', rows);
  }

  /// Table 349 /ColSpan.
  PdfStructureAttributes setColSpan(int columns) {
    if (columns < 1) {
      throw ArgumentError.value(
          columns, 'columns', '/ColSpan must be at least 1.');
    }
    return _putInt('ColSpan', columns);
  }

  /// Table 349 /Headers, the element identifiers of the /TH cells that head
  /// this cell.
  PdfStructureAttributes setHeaders(List<String> headerIds) {
    final array = PdfArray();
    for (final id in headerIds) {
      array.add(PdfString(id));
    }
    return put(PdfName('Headers'), array);
  }

  /// Table 349 /Scope: Row, Column or Both. Only meaningful on /TH.
  PdfStructureAttributes setScope(String value) {
    _expect('Scope', value, scopes);
    return _putName('Scope', value);
  }

  /// The values Table 349 allows for /Scope.
  static const Set<String> scopes = {'Row', 'Column', 'Both'};

  /// Table 349 /Summary, which belongs on a /Table element.
  PdfStructureAttributes setSummary(String value) =>
      put(PdfName('Summary'), PdfString(value));

  @override
  bool requiresIndirectStorage() => false;

  static List<double> _rgb(List<double> rgb) {
    if (rgb.length != 3) {
      throw ArgumentError.value(
          rgb, 'rgb', 'A colour attribute needs three components.');
    }
    for (final component in rgb) {
      if (component < 0 || component > 1) {
        throw ArgumentError.value(rgb, 'rgb',
            'Colour components run from 0.0 to 1.0.');
      }
    }
    return rgb;
  }

  static void _expect(String attribute, String value, Set<String> allowed) {
    if (!allowed.contains(value)) {
      throw ArgumentError.value(value, attribute,
          'Allowed values are ${allowed.join(', ')}.');
    }
  }
}
