import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_object.dart';

/// One defect found in a logical structure tree.
///
/// The scan reports facts about the tree; the caller decides which standard's
/// clause the fact breaks, because PDF/A level A and PDF/UA state the same
/// requirements in different words.
class StructureIssue {
  /// Stable identifier, e.g. `heading-level-skipped`.
  final String code;

  /// What was observed, in English.
  final String message;

  /// The ISO 14289-1 clause the rule comes from.
  final String uaClause;

  const StructureIssue(this.code, this.message, this.uaClause);
}

/// The structure types ISO 32000-1 14.8.4 defines.
///
/// A tree may use any other type, but only if `/RoleMap` says what standard
/// type it stands for; otherwise nothing can interpret it.
const Set<String> kStandardStructureTypes = {
  // Grouping
  'Document', 'Part', 'Art', 'Sect', 'Div', 'BlockQuote', 'Caption', 'TOC',
  'TOCI', 'Index', 'NonStruct', 'Private', 'DocumentFragment', 'Aside',
  // Block level
  'P', 'H', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'H7', 'Title', 'Sub',
  'L', 'LI', 'Lbl', 'LBody',
  'Table', 'TR', 'TH', 'TD', 'THead', 'TBody', 'TFoot',
  // Inline level
  'Span', 'Quote', 'Note', 'Reference', 'BibEntry', 'Code', 'Link', 'Annot',
  'Ruby', 'RB', 'RT', 'RP', 'Warichu', 'WT', 'WP', 'Em', 'Strong',
  // Illustration
  'Figure', 'Formula', 'Form', 'Artifact',
};

/// Structure types that replace something a reader cannot read and so need a
/// text alternative.
const Set<String> kNeedsAlternative = {'Figure', 'Formula'};

/// Reads a structure tree and reports what is wrong with its shape.
///
/// Shape is all a machine can judge: whether headings step down one level at a
/// time, whether a table is rectangular and says which cell heads which
/// column, whether a list is built out of list items, and whether every type
/// used means something. Whether the tree describes the page — the reading
/// order, the aptness of an alternative text — is not decidable here and is
/// reported by the verifiers as unverified.
class StructureScan {
  final List<StructureIssue> issues = [];

  /// Structure types encountered, in the order first seen.
  final Set<String> types = {};

  /// True when the tree carried at least one element.
  bool hasElements = false;
}

/// Walks [root] (a `/StructTreeRoot`) and collects its defects.
Future<StructureScan> scanStructureTree(PdfDictionary root) async {
  final scan = StructureScan();
  final roleMap = await root.dictionaryEntry(PdfName('RoleMap'));
  final state = _WalkState(scan, roleMap);
  await _walk(root, state, 0, <PdfDictionary>{});
  return scan;
}

class _WalkState {
  final StructureScan scan;
  final PdfDictionary? roleMap;

  /// Level of the last heading seen, so a skipped level can be spotted.
  int lastHeadingLevel = 0;

  _WalkState(this.scan, this.roleMap);
}

const int _maxDepth = 128;

Future<void> _walk(
  PdfDictionary node,
  _WalkState state,
  int depth,
  Set<PdfDictionary> seen,
) async {
  if (depth > _maxDepth || !seen.add(node)) return;

  final type = (await node.nameEntry(PdfName('S')))?.getValue();
  if (type != null) {
    state.scan.hasElements = true;
    state.scan.types.add(type);
    await _checkType(type, node, state);
  }

  for (final kid in await structureChildren(node)) {
    await _walk(kid, state, depth + 1, seen);
  }
}

Future<void> _checkType(
  String type,
  PdfDictionary node,
  _WalkState state,
) async {
  final scan = state.scan;
  final resolved = await _resolveRole(type, state);

  if (resolved == null) {
    scan.issues.add(StructureIssue(
      'unmapped-structure-type',
      'The structure type /$type is not one ISO 32000-1 defines and the '
          'role map does not say what standard type it stands for, so nothing '
          'can interpret it.',
      'ISO 14289-1:7.1',
    ));
    return;
  }

  if (kNeedsAlternative.contains(resolved)) {
    final alt = (await node.stringEntry(PdfName('Alt')))?.getValue();
    final actual = (await node.stringEntry(PdfName('ActualText')))?.getValue();
    if ((alt == null || alt.trim().isEmpty) &&
        (actual == null || actual.trim().isEmpty)) {
      scan.issues.add(StructureIssue(
        'figure-without-alternative',
        'A /$type structure element has neither /Alt nor /ActualText, so it '
            'is silent to a screen reader.',
        'ISO 14289-1:7.3',
      ));
    }
  }

  final headingLevel = _headingLevel(resolved);
  if (headingLevel != null) {
    if (headingLevel > state.lastHeadingLevel + 1) {
      scan.issues.add(StructureIssue(
        'heading-level-skipped',
        state.lastHeadingLevel == 0
            ? 'The first heading in the document is /$resolved; a heading '
                'outline has to start at H1.'
            : 'A /H${state.lastHeadingLevel} heading is followed by '
                '/$resolved, which skips a level. Assistive technology reads '
                'the outline as a tree, and a skipped level breaks it.',
        'ISO 14289-1:7.4.2',
      ));
    }
    state.lastHeadingLevel = headingLevel;
  }

  if (resolved == 'Table') await _checkTable(node, state);
  if (resolved == 'L') await _checkList(node, state);
  if (resolved == 'LI') await _checkListItem(node, state);
}

int? _headingLevel(String type) {
  if (type.length != 2 || !type.startsWith('H')) return null;
  return int.tryParse(type.substring(1));
}

/// Maps a structure type through `/RoleMap` until it lands on a standard type.
///
/// Returns null when the chain never reaches one.
Future<String?> _resolveRole(String type, _WalkState state) async {
  var current = type;
  for (var hops = 0; hops < 8; hops++) {
    if (kStandardStructureTypes.contains(current)) return current;
    final mapped = await state.roleMap?.nameEntry(PdfName(current));
    if (mapped == null) return null;
    current = mapped.getValue();
  }
  return null;
}

/// The structure element children of [node], skipping marked-content
/// references and object references, which are leaves.
Future<List<PdfDictionary>> structureChildren(PdfDictionary node) async {
  final kids = await node.get(PdfName('K'));
  if (kids == null) return const [];
  final result = <PdfDictionary>[];

  Future<void> consider(PdfObject? candidate) async {
    if (candidate == null) return;
    if (candidate.objectKind() != PdfObjectType.dictionary) return;
    final dictionary = candidate as PdfDictionary;
    // /MCR and /OBJR children point at content, not at more structure.
    final kind = (await dictionary.nameEntry(PdfName.type))?.getValue();
    if (kind == 'MCR' || kind == 'OBJR') return;
    result.add(dictionary);
  }

  if (kids.objectKind() == PdfObjectType.array) {
    final array = kids as PdfArray;
    for (var i = 0; i < array.size(); i++) {
      await consider(await array.get(i));
    }
  } else {
    await consider(kids);
  }
  return result;
}

// --- tables -----------------------------------------------------------------

class _Cell {
  final String type; // TH or TD
  final int rowSpan;
  final int colSpan;
  final PdfDictionary node;
  const _Cell(this.type, this.rowSpan, this.colSpan, this.node);
}

Future<void> _checkTable(PdfDictionary table, _WalkState state) async {
  final rows = <List<_Cell>>[];
  await _collectRows(table, state, rows, 0);
  if (rows.isEmpty) return;

  // Lay the cells out on a grid so that spans are honoured; a table whose
  // rows then have different widths is not a table a reader can navigate.
  final occupied = <String, bool>{};
  final widths = <int>[];
  for (var r = 0; r < rows.length; r++) {
    var column = 0;
    for (final cell in rows[r]) {
      while (occupied['$r:$column'] == true) {
        column++;
      }
      for (var dr = 0; dr < cell.rowSpan; dr++) {
        for (var dc = 0; dc < cell.colSpan; dc++) {
          occupied['${r + dr}:${column + dc}'] = true;
        }
      }
      column += cell.colSpan;
    }
    var width = 0;
    while (occupied['$r:$width'] == true) {
      width++;
    }
    widths.add(width);
  }

  final expected = widths.reduce((a, b) => a > b ? a : b);
  if (widths.any((w) => w != expected)) {
    state.scan.issues.add(StructureIssue(
      'table-not-rectangular',
      'The table has rows of ${widths.toSet().toList()..sort()} cells once '
          'row and column spans are counted. A reader navigating by column '
          'cannot line the cells up.',
      'ISO 14289-1:7.5',
    ));
  }

  final cells = rows.expand((row) => row).toList(growable: false);
  final headers = cells.where((c) => c.type == 'TH').toList(growable: false);
  if (headers.isEmpty) {
    state.scan.issues.add(StructureIssue(
      'table-without-header-cells',
      'The table has no /TH cell, so no cell says what the values under it '
          'mean.',
      'ISO 14289-1:7.5',
    ));
    return;
  }

  // A header cell says what it heads either through /Scope, or by being named
  // from the data cells through /Headers. One of the two has to be there.
  final dataCells = cells.where((c) => c.type == 'TD');
  final everyDataCellPointsAtHeaders = dataCells.isEmpty
      ? false
      : (await Future.wait(dataCells.map((c) => _hasEntry(c.node, 'Headers'))))
          .every((present) => present);
  for (final header in headers) {
    final scope = await _attributeValue(header.node, 'Scope');
    if (scope == null && !everyDataCellPointsAtHeaders) {
      state.scan.issues.add(const StructureIssue(
        'header-cell-without-scope',
        'A /TH cell declares no /Scope attribute and the data cells do not '
            'name it through /Headers, so nothing associates the header with '
            'the cells it heads.',
        'ISO 14289-1:7.5',
      ));
      break;
    }
    if (scope != null && !const {'Row', 'Column', 'Both'}.contains(scope)) {
      state.scan.issues.add(StructureIssue(
        'header-cell-bad-scope',
        'A /TH cell declares /Scope /$scope; ISO 32000-1 allows only Row, '
            'Column and Both.',
        'ISO 14289-1:7.5',
      ));
      break;
    }
  }
}

/// Collects the rows of a table, descending through THead/TBody/TFoot.
Future<void> _collectRows(
  PdfDictionary node,
  _WalkState state,
  List<List<_Cell>> rows,
  int depth,
) async {
  if (depth > 8) return;
  for (final kid in await structureChildren(node)) {
    final raw = (await kid.nameEntry(PdfName('S')))?.getValue();
    final type = raw == null ? null : await _resolveRole(raw, state);
    switch (type) {
      case 'THead':
      case 'TBody':
      case 'TFoot':
        await _collectRows(kid, state, rows, depth + 1);
      case 'TR':
        rows.add(await _collectCells(kid, state));
      default:
        break;
    }
  }
}

Future<List<_Cell>> _collectCells(
  PdfDictionary row,
  _WalkState state,
) async {
  final cells = <_Cell>[];
  for (final kid in await structureChildren(row)) {
    final raw = (await kid.nameEntry(PdfName('S')))?.getValue();
    final type = raw == null ? null : await _resolveRole(raw, state);
    if (type != 'TH' && type != 'TD') continue;
    final rowSpan = await _attributeInteger(kid, 'RowSpan') ?? 1;
    final colSpan = await _attributeInteger(kid, 'ColSpan') ?? 1;
    cells.add(_Cell(
      type!,
      rowSpan < 1 ? 1 : rowSpan,
      colSpan < 1 ? 1 : colSpan,
      kid,
    ));
  }
  return cells;
}

Future<bool> _hasEntry(PdfDictionary node, String key) async {
  if (node.containsKey(PdfName(key))) return true;
  return await _attributeObject(node, key) != null;
}

/// Reads an attribute from `/A`, which is either one attribute dictionary or
/// an array of them, optionally interleaved with revision numbers.
Future<PdfObject?> _attributeObject(PdfDictionary node, String key) async {
  final attributes = await node.get(PdfName('A'));
  if (attributes == null) return null;
  if (attributes.objectKind() == PdfObjectType.dictionary) {
    return (attributes as PdfDictionary).get(PdfName(key));
  }
  if (attributes.objectKind() == PdfObjectType.array) {
    final array = attributes as PdfArray;
    for (var i = 0; i < array.size(); i++) {
      final entry = await array.dictionaryEntry(i);
      final value = await entry?.get(PdfName(key));
      if (value != null) return value;
    }
  }
  return null;
}

Future<String?> _attributeValue(PdfDictionary node, String key) async {
  final direct = await node.nameEntry(PdfName(key));
  if (direct != null) return direct.getValue();
  final value = await _attributeObject(node, key);
  if (value != null && value.objectKind() == PdfObjectType.name) {
    return (value as PdfName).getValue();
  }
  return null;
}

Future<int?> _attributeInteger(PdfDictionary node, String key) async {
  final direct = await node.integerEntry(PdfName(key));
  if (direct != null) return direct;
  final value = await _attributeObject(node, key);
  if (value is PdfNumber) return value.intValue();
  return null;
}

// --- lists ------------------------------------------------------------------

Future<void> _checkList(PdfDictionary list, _WalkState state) async {
  for (final kid in await structureChildren(list)) {
    final raw = (await kid.nameEntry(PdfName('S')))?.getValue();
    if (raw == null) continue;
    final type = await _resolveRole(raw, state);
    if (type == 'LI' || type == 'Caption') continue;
    state.scan.issues.add(StructureIssue(
      'list-child-not-item',
      'A /L list contains a /$raw child. A list is a sequence of /LI items, '
          'so a reader announcing "list of n items" would be wrong.',
      'ISO 14289-1:7.6',
    ));
    return;
  }
}

Future<void> _checkListItem(PdfDictionary item, _WalkState state) async {
  for (final kid in await structureChildren(item)) {
    final raw = (await kid.nameEntry(PdfName('S')))?.getValue();
    if (raw == null) continue;
    final type = await _resolveRole(raw, state);
    if (type == 'Lbl' || type == 'LBody') continue;
    state.scan.issues.add(StructureIssue(
      'list-item-child-unexpected',
      'A /LI item contains a /$raw child; ISO 32000-1 allows only /Lbl and '
          '/LBody there.',
      'ISO 14289-1:7.6',
    ));
    return;
  }
}
