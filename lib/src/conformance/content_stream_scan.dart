import 'dart:typed_data';

import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_string.dart';
import '../render/content_parser.dart';

/// The three device colour spaces a conformance profile constrains.
const Set<String> kDeviceColourSpaces = {
  'DeviceGray',
  'DeviceRGB',
  'DeviceCMYK',
};

/// Resource categories a content stream can name, mapped to the operators that
/// name them. A name used by an operator must exist in the matching
/// sub-dictionary of the page's `/Resources`; ISO 32000-1 7.8.3 makes that the
/// only way a content stream can reach an object.
const Map<String, String> _resourceOperators = {
  'Tf': 'Font',
  'Do': 'XObject',
  'gs': 'ExtGState',
  'sh': 'Shading',
};

/// What a pass over one content stream observed.
///
/// The scan is deliberately a collection of facts rather than a verdict: PDF/A
/// and PDF/UA read the same facts and draw different conclusions from them.
class ContentStreamScan {
  /// Device colour spaces the stream selected, by any of the colour operators
  /// or through a named colour space that resolves to one.
  final Set<String> deviceColourSpaces = {};

  /// Text rendering modes set with `Tr`. Mode 0 is implied whenever text is
  /// drawn without setting one.
  final Set<int> textRenderModes = {};

  /// Resource names the stream used, keyed by category (`Font`, `XObject`,
  /// `ExtGState`, `Shading`, `ColorSpace`), each mapped to the names used.
  final Map<String, Set<String>> usedResources = {};

  /// Resource names the stream used that the resource dictionary does not
  /// define, formatted as `Font/F1`.
  final Set<String> missingResources = {};

  /// True when `q` and `Q` do not pair up, either because a `Q` appeared with
  /// no open state or because the stream ended with one still open.
  bool unbalancedSaveRestore = false;

  /// True when `BT`/`ET` do not pair up, or nest.
  bool unbalancedTextObjects = false;

  /// True when `BMC`/`BDC` and `EMC` do not pair up.
  bool unbalancedMarkedContent = false;

  /// True when something was painted while no marked-content sequence was
  /// open, so the mark-up cannot say whether it is content or decoration.
  bool paintsOutsideMarkedContent = false;

  /// True when something was painted inside a marked-content sequence that is
  /// neither an artifact nor carries an `/MCID`, so it belongs to no structure
  /// element.
  bool paintsInUnidentifiedMarkedContent = false;

  /// Marked-content tags opened by `BMC`/`BDC`.
  final Set<String> markedContentTags = {};

  /// The strings shown by the text operators, grouped by the font resource
  /// name that was selected when they were drawn. This is what lets a caller
  /// ask whether the codes actually used are covered by a `/ToUnicode` map,
  /// rather than only whether the map exists.
  final Map<String, List<Uint8List>> shownTextByFont = {};

  /// True when a text operator ran with no font selected, which makes the page
  /// undrawable as written.
  bool textWithoutFont = false;

  /// How many strings are kept per font. A page that draws the same font a
  /// thousand times says nothing new after the first few dozen strings.
  static const int stringsKeptPerFont = 64;

  /// The parse error that stopped the scan, when the stream is not valid
  /// content.
  String? failure;

  bool get parsed => failure == null;
}

/// Operators that put marks on the page.
///
/// `Do` is included because an XObject invocation paints whatever the object
/// contains, and `EI` because the parser reports a complete inline image under
/// its opening `BI`.
const Set<String> _paintingOperators = {
  'Tj', 'TJ', "'", '"', // text
  'S', 's', 'f', 'F', 'f*', 'B', 'B*', 'b', 'b*', // paths
  'sh', 'Do', 'BI', // shadings, xobjects, inline images
};

/// Reads one content stream and reports what it does.
///
/// [resources] is the resource dictionary in scope, used to resolve the names
/// the stream mentions. A null resource dictionary means the stream declares
/// none, which is itself why every name it uses is reported missing.
Future<ContentStreamScan> scanContentStream(
  Uint8List content,
  PdfDictionary? resources,
) async {
  final scan = ContentStreamScan();
  final List<PdfContentOperation> operations;
  try {
    operations = PdfContentParser.parse(content).toList(growable: false);
  } on PdfContentException catch (error) {
    scan.failure = error.message;
    return scan;
  } on FormatException catch (error) {
    scan.failure = error.message;
    return scan;
  }

  var saveDepth = 0;
  var inText = false;
  String? currentFont;
  // Each open marked-content sequence, described by whether it is an artifact
  // and whether it carries an /MCID.
  final markedContent = <_MarkedContent>[];

  for (final operation in operations) {
    final operator = operation.operator;

    switch (operator) {
      case 'q':
        saveDepth++;
      case 'Q':
        saveDepth--;
        if (saveDepth < 0) {
          scan.unbalancedSaveRestore = true;
          saveDepth = 0;
        }
      case 'BT':
        if (inText) scan.unbalancedTextObjects = true;
        inText = true;
      case 'ET':
        if (!inText) scan.unbalancedTextObjects = true;
        inText = false;
      case 'Tf':
        currentFont = operation.name(0);
      case 'Tr':
        final mode = operation.number(0);
        if (mode != null) scan.textRenderModes.add(mode.toInt());
      case 'Tj':
      case "'":
        _recordText(scan, currentFont, operation.operands, 0);
      case '"':
        _recordText(scan, currentFont, operation.operands, 2);
      case 'TJ':
        final array = operation.operands.isEmpty ? null : operation.operands[0];
        if (array != null && array.objectKind() == PdfObjectType.array) {
          final items = array as PdfArray;
          for (var i = 0; i < items.size(); i++) {
            _recordText(scan, currentFont, [await items.get(i)], 0);
          }
        }
      case 'g':
      case 'G':
        scan.deviceColourSpaces.add('DeviceGray');
      case 'rg':
      case 'RG':
        scan.deviceColourSpaces.add('DeviceRGB');
      case 'k':
      case 'K':
        scan.deviceColourSpaces.add('DeviceCMYK');
      case 'cs':
      case 'CS':
        final name = operation.name(0);
        if (name != null) {
          scan.deviceColourSpaces
              .addAll(await _deviceSpacesOf(name, resources, scan));
        }
      case 'BMC':
      case 'BDC':
        markedContent.add(await _openMarkedContent(operation, resources, scan));
      case 'EMC':
        if (markedContent.isEmpty) {
          scan.unbalancedMarkedContent = true;
        } else {
          markedContent.removeLast();
        }
    }

    final category = _resourceOperators[operator];
    if (category != null) {
      final name = operation.name(0);
      if (name != null) {
        await _useResource(category, name, resources, scan);
      }
    }

    if (_paintingOperators.contains(operator)) {
      if (markedContent.isEmpty) {
        scan.paintsOutsideMarkedContent = true;
      } else if (!markedContent.any((m) => m.isArtifact) &&
          !markedContent.any((m) => m.hasMcid)) {
        scan.paintsInUnidentifiedMarkedContent = true;
      }
    }
  }

  if (saveDepth != 0) scan.unbalancedSaveRestore = true;
  if (inText) scan.unbalancedTextObjects = true;
  if (markedContent.isNotEmpty) scan.unbalancedMarkedContent = true;
  return scan;
}

/// Records the string shown by a text operator against the font in effect.
void _recordText(
  ContentStreamScan scan,
  String? font,
  List<PdfObject?> operands,
  int index,
) {
  if (index >= operands.length) return;
  final operand = operands[index];
  if (operand is! PdfString) return;
  if (font == null) {
    scan.textWithoutFont = true;
    return;
  }
  final bytes = operand.getValueBytes();
  if (bytes == null || bytes.isEmpty) return;
  final kept = scan.shownTextByFont.putIfAbsent(font, () => <Uint8List>[]);
  if (kept.length < ContentStreamScan.stringsKeptPerFont) kept.add(bytes);
}

class _MarkedContent {
  final bool isArtifact;
  final bool hasMcid;
  const _MarkedContent(this.isArtifact, this.hasMcid);
}

Future<_MarkedContent> _openMarkedContent(
  PdfContentOperation operation,
  PdfDictionary? resources,
  ContentStreamScan scan,
) async {
  final tag = operation.name(0);
  if (tag != null) scan.markedContentTags.add(tag);
  if (operation.operator == 'BMC' || operation.operands.length < 2) {
    return _MarkedContent(tag == 'Artifact', false);
  }
  final property = operation.operands[1];
  PdfDictionary? dictionary;
  if (property.objectKind() == PdfObjectType.dictionary) {
    dictionary = property as PdfDictionary;
  } else if (property.objectKind() == PdfObjectType.name) {
    final name = (property as PdfName).getValue();
    final properties = await resources?.dictionaryEntry(PdfName('Properties'));
    dictionary = await properties?.dictionaryEntry(PdfName(name));
    if (properties == null || dictionary == null) {
      scan.missingResources.add('Properties/$name');
    }
    (scan.usedResources['Properties'] ??= <String>{}).add(name);
  }
  final mcid =
      dictionary == null ? null : await dictionary.get(PdfName('MCID'));
  return _MarkedContent(tag == 'Artifact', mcid is PdfNumber);
}

Future<void> _useResource(
  String category,
  String name,
  PdfDictionary? resources,
  ContentStreamScan scan,
) async {
  (scan.usedResources[category] ??= <String>{}).add(name);
  final group = await resources?.dictionaryEntry(PdfName(category));
  if (group == null || !group.containsKey(PdfName(name))) {
    scan.missingResources.add('$category/$name');
  }
}

/// The device colour spaces a named colour space ultimately paints through.
///
/// An `/Indexed` palette, a `/Separation` ink and a `/DeviceN` set all name a
/// base or alternate space that is what actually reaches the device, so they
/// are followed. `/ICCBased`, `/CalRGB`, `/CalGray` and `/Lab` are
/// device independent and stop the walk.
Future<Set<String>> _deviceSpacesOf(
  String name,
  PdfDictionary? resources,
  ContentStreamScan scan,
) async {
  if (kDeviceColourSpaces.contains(name)) return {name};
  if (name == 'Pattern') return const {};

  (scan.usedResources['ColorSpace'] ??= <String>{}).add(name);
  final group = await resources?.dictionaryEntry(PdfName.colorSpace);
  final entry = await group?.get(PdfName(name));
  if (entry == null) {
    scan.missingResources.add('ColorSpace/$name');
    return const {};
  }
  return _deviceSpacesOfObject(entry, 0);
}

Future<Set<String>> _deviceSpacesOfObject(PdfObject space, int depth) async {
  if (depth > 8) return const {};
  if (space.objectKind() == PdfObjectType.name) {
    final value = (space as PdfName).getValue();
    return kDeviceColourSpaces.contains(value) ? {value} : const {};
  }
  if (space.objectKind() != PdfObjectType.array) return const {};

  final array = space as PdfArray;
  if (array.size() == 0) return const {};
  final family = (await array.nameEntry(0))?.getValue();
  switch (family) {
    case 'Indexed':
      final base = await array.get(1);
      return base == null ? const {} : _deviceSpacesOfObject(base, depth + 1);
    case 'Separation':
    case 'DeviceN':
      final alternate = array.size() > 2 ? await array.get(2) : null;
      return alternate == null
          ? const {}
          : _deviceSpacesOfObject(alternate, depth + 1);
    case 'Pattern':
      final underlying = array.size() > 1 ? await array.get(1) : null;
      return underlying == null
          ? const {}
          : _deviceSpacesOfObject(underlying, depth + 1);
    default:
      return family != null && kDeviceColourSpaces.contains(family)
          ? {family}
          : const {};
  }
}
