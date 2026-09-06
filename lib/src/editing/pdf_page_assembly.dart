import 'dart:collection';
import 'dart:typed_data';
import 'pdf_form_merge.dart';
export 'pdf_form_merge.dart' show PdfMergeSignaturePolicy;
import 'pdf_text_extraction.dart' show PdfGraphicsEnvelope;

import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_page.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/reader_properties.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../kernel/pdf/pdf_writer.dart';

/// Object import retains selected interactive features. Flatten draws page
/// content and normal annotation appearances into forms, removing interaction.
/// Visible annotations without an appearance fail instead of disappearing.
enum PdfMergeMode { objectImport, flatten }

/// A source document and an ordered, one-based selection of its pages.
/// A null selection includes every page. Repeated page numbers are allowed.
class PdfPageSelection {
  final Uint8List bytes;
  final List<int>? pages;
  final CraftReaderProperties? readerProperties;
  PdfPageSelection(this.bytes,
      {List<int>? pages, CraftReaderProperties? readerProperties})
      : pages = pages == null ? null : List.unmodifiable(pages),
        readerProperties = readerProperties == null
            ? null
            : CraftReaderProperties.from(readerProperties);
}

/// Assembles PDF pages without native libraries or external packages.
/// Strict defaults reject interactive structures needing reconciliation.
/// Opt-in modes preserve supported annotations, forms, outlines, destination
/// links, layers and page labels, or flatten visible appearances into content.
/// Inputs are not modified. Unsupported actions and tagged structure fail.
class PdfPageAssembly {
  /// [mode] flatten draws /AP/N into page coordinates and discards form fields,
  /// annotations and signature dictionaries. Output signatures are not valid
  /// signatures of the new file; only their existing visual appearances remain.
  /// [resolveNamedDestinations] converts source destination names to local
  /// explicit arrays; targets must occur in the selected page set.
  /// [preserveForms] imports supported forms under [signaturePolicy].
  /// [preserveLayers] reconciles OCG identity and static default visibility;
  /// alternate configurations and automatic state rules remain unsupported.
  /// [preservePageLabels] preserves each selected page label, including /St
  /// offsets after reordering or repeating pages.
  /// [includeAnnotations] copies supported page-local annotations and URI links.
  /// The default retains strict rejection of pages containing annotations.
  /// Widgets require [preserveForms]; local destinations require
  /// [resolveNamedDestinations]. Scripts and unsupported relationships fail.
  /// [preserveOutlines] rebuilds local explicit destinations. A destination to
  /// an omitted page fails; repeated selections target their first occurrence.
  /// Separate source entries always retain independent outline destinations.
  static Future<Uint8List> merge(List<PdfPageSelection> sources,
      {bool includeAnnotations = false,
      bool preserveOutlines = false,
      bool resolveNamedDestinations = false,
      PdfMergeMode mode = PdfMergeMode.objectImport,
      bool preserveForms = false,
      bool preserveLayers = false,
      bool preservePageLabels = false,
      PdfMergeSignaturePolicy signaturePolicy =
          PdfMergeSignaturePolicy.reject}) async {
    if (sources.isEmpty)
      throw ArgumentError('At least one source is required.');
    final opened = <CraftPdfDocument>[];
    final selected = <List<CraftPdfPage>>[];
    final formPlans = <PdfFormMergePlan?>[];
    final outlines = <List<_OutlineEntry>>[];
    try {
      // Validate every source before allocating the output document.
      for (final source in sources) {
        final reader =
            CraftPdfReader.fromBytes(source.bytes, source.readerProperties);
        final doc = await CraftPdfDocument.open(reader);
        opened.add(doc);
        if (reader.encrypted) {
          throw UnsupportedError('Encrypted page assembly is not supported.');
        }
        final catalog = doc.rootCatalog().pdfRepresentation();
        for (final name in [
          if (!preserveForms && mode != PdfMergeMode.flatten) 'AcroForm',
          'StructTreeRoot',
          if (!preserveOutlines) 'Outlines',
          if (!resolveNamedDestinations) 'Names',
          if (!resolveNamedDestinations) 'Dests',
          if (!preserveLayers) 'OCProperties',
          if (!preservePageLabels) 'PageLabels',
          'OpenAction',
          'AA',
          'Collection',
        ]) {
          if (catalog.containsKey(CraftPdfName(name))) {
            throw UnsupportedError('Page assembly cannot reconcile /$name.');
          }
        }
        if (resolveNamedDestinations) await _resolveNames(doc);
        final count = doc.pageTotal();
        final numbers = source.pages ?? List.generate(count, (i) => i + 1);
        final pages = <CraftPdfPage>[];
        for (final number in numbers) {
          if (number < 1 || number > count) {
            throw RangeError.range(number, 1, count, 'page');
          }
          final page = (await doc.pageAt(number))!;
          for (final name in [
            if (!includeAnnotations &&
                !preserveForms &&
                mode != PdfMergeMode.flatten)
              'Annots',
            'AA',
            'B',
            'PresSteps',
            'StructParents'
          ]) {
            if (page.pdfRepresentation().containsKey(CraftPdfName(name))) {
              throw UnsupportedError('Page assembly cannot reconcile /$name.');
            }
          }
          if ((includeAnnotations || preserveForms) &&
              mode != PdfMergeMode.flatten)
            await _validateAnnotations(page,
                allowWidgets: preserveForms,
                allowLocalLinks: resolveNamedDestinations);
          pages.add(page);
        }
        formPlans.add(preserveForms && mode != PdfMergeMode.flatten
            ? await PdfFormMerge.prepare(doc, pages,
                signaturePolicy: signaturePolicy)
            : null);
        selected.add(pages);
        outlines.add(preserveOutlines
            ? await _readOutlines(catalog, pages)
            : <_OutlineEntry>[]);
      }
      if (selected.every((pages) => pages.isEmpty)) {
        throw ArgumentError('The page selection is empty.');
      }
      final bytes = BytesBuilder();
      final output =
          await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(bytes));
      final mergedOutlines = <CraftPdfDictionary>[];
      final labelPairs = CraftPdfArray();
      var outputPageIndex = 0;
      for (var sourceIndex = 0; sourceIndex < selected.length; sourceIndex++) {
        final pages = selected[sourceIndex];
        final layerCopies = preserveLayers
            ? await _importLayers(opened[sourceIndex], output)
            : <CraftPdfObject, CraftPdfObject>{};
        final labels = preservePageLabels
            ? await _pageLabels(opened[sourceIndex])
            : <int, CraftPdfDictionary>{};
        final pageTargets =
            HashMap<CraftPdfDictionary, CraftPdfDictionary>.identity();
        final repeatedTargets =
            HashMap<CraftPdfDictionary, List<CraftPdfDictionary>>.identity();
        final targets = [
          for (var i = 0; i < pages.length; i++)
            CraftPdfDictionary()..attachToDocument(output)
        ];
        for (var index = 0; index < pages.length; index++) {
          pageTargets.putIfAbsent(
              pages[index].pdfRepresentation(), () => targets[index]);
          repeatedTargets
              .putIfAbsent(pages[index].pdfRepresentation(), () => [])
              .add(targets[index]);
        }
        for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
          final page = pages[pageIndex];
          // A fresh map per page also isolates repeated pages for future edits.
          final copier =
              _PageGraphCopy(output, protectPageReferences: includeAnnotations);
          copier.copies.addAll(layerCopies);
          final dictionary = targets[pageIndex];
          if (resolveNamedDestinations) copier.copies.addAll(pageTargets);
          copier.copies[page.pdfRepresentation()] = dictionary;
          dictionary.attachToDocument(output);
          pageTargets.putIfAbsent(page.pdfRepresentation(), () => dictionary);
          for (final entry in await page.pdfRepresentation().entrySet()) {
            if (entry.key == CraftPdfName.parent) continue;
            if (entry.key == CraftPdfName.annots &&
                (preserveForms || mode == PdfMergeMode.flatten)) {
              if (mode == PdfMergeMode.flatten) continue;
              final annotations = await page
                  .pdfRepresentation()
                  .arrayEntry(CraftPdfName.annots);
              final retained = CraftPdfArray();
              if (annotations != null)
                for (var i = 0; i < annotations.size(); i++) {
                  final annotation = await annotations.dictionaryEntry(i);
                  if (annotation == null)
                    throw FormatException('Invalid annotation.');
                  if ((await annotation.nameEntry(CraftPdfName.subtype))
                          ?.getValue() !=
                      'Widget') retained.add(await copier.copy(annotation));
                }
              if (retained.size() != 0)
                dictionary.put(CraftPdfName.annots, retained);
              continue;
            }
            dictionary.put(entry.key, await copier.copy(entry.value));
          }
          // PDF page-tree attributes may live on an ancestor, not the leaf.
          for (final name in ['Resources', 'MediaBox', 'CropBox', 'Rotate']) {
            final key = CraftPdfName(name);
            if (dictionary.containsKey(key)) continue;
            CraftPdfDictionary? ancestor = page.pdfRepresentation();
            final visited = HashSet<CraftPdfDictionary>.identity();
            while (ancestor != null) {
              if (!visited.add(ancestor) || visited.length > 256) {
                throw FormatException('Invalid page ancestry during assembly.');
              }
              final value = await ancestor.get(key);
              if (value != null) {
                dictionary.put(key, await copier.copy(value));
                break;
              }
              ancestor = await ancestor.dictionaryEntry(CraftPdfName.parent);
            }
          }
          if (mode == PdfMergeMode.flatten) {
            final box = await dictionary.arrayEntry(CraftPdfName.mediaBox);
            if (box == null)
              throw FormatException('Flattening requires a page MediaBox.');
            final form = CraftPdfStream.withBytes(
                PdfGraphicsEnvelope.wrap(await page.contentPayload()))
              ..put(CraftPdfName.type, CraftPdfName.xObject)
              ..put(CraftPdfName.subtype, CraftPdfName.form)
              ..put(CraftPdfName.bBox, box)
              ..put(
                  CraftPdfName.resources,
                  (await dictionary.dictionaryEntry(CraftPdfName.resources)) ??
                      CraftPdfDictionary());
            form.attachToDocument(output);
            dictionary.put(
                CraftPdfName.resources,
                CraftPdfDictionary()
                  ..put(CraftPdfName.xObject,
                      CraftPdfDictionary()..put(CraftPdfName('Page'), form)));
            dictionary.put(
                CraftPdfName.contents,
                CraftPdfStream.withBytes(
                    Uint8List.fromList('q /Page Do Q'.codeUnits)));
          }
          if (mode == PdfMergeMode.flatten) {
            await _flattenAnnotations(
                page, dictionary, copier, output, signaturePolicy);
          }
          if (preservePageLabels) {
            final originalIndex =
                opened[sourceIndex].pageOrdinal(pages[pageIndex]) - 1;
            var ruleStart = -1;
            for (final start in labels.keys) {
              if (start <= originalIndex && start > ruleStart)
                ruleStart = start;
            }
            final rule = ruleStart < 0
                ? (CraftPdfDictionary()
                  ..put(CraftPdfName('S'), CraftPdfName('D')))
                : labels[ruleStart]!;
            final copy = CraftPdfDictionary();
            for (final entry in await rule.entrySet()) {
              copy.put(entry.key, (await rule.get(entry.key, true))!.clone());
            }
            if (await rule.nameEntry(CraftPdfName('S')) != null) {
              final first =
                  (await rule.numberEntry(CraftPdfName('St')))?.intValue() ?? 1;
              copy.put(
                  CraftPdfName('St'),
                  CraftPdfNumber.fromInt(
                      first + originalIndex - (ruleStart < 0 ? 0 : ruleStart)));
            }
            labelPairs.add(CraftPdfNumber.fromInt(outputPageIndex));
            labelPairs.add(copy);
          }
          outputPageIndex++;
          await output.appendPageObject(CraftPdfPage(dictionary));
        }
        final formPlan = formPlans[sourceIndex];
        if (formPlan != null) {
          final copier = _PageGraphCopy(output, protectPageReferences: true)
            ..copies.addAll(pageTargets);
          await formPlan.importInto(output, pageTargets, copier.copy,
              repeatedTargets: repeatedTargets);
        }
        mergedOutlines.addAll(await _writeOutlineEntries(
            outlines[sourceIndex], output, pageTargets));
      }
      if (mergedOutlines.isNotEmpty) {
        final root = CraftPdfDictionary()
          ..put(CraftPdfName.type, CraftPdfName('Outlines'))
          ..attachToDocument(output);
        _linkOutlineSiblings(root, mergedOutlines);
        root.put(CraftPdfName('Count'),
            CraftPdfNumber.fromInt(await _visibleOutlineCount(mergedOutlines)));
        output
            .rootCatalog()
            .pdfRepresentation()
            .put(CraftPdfName('Outlines'), root);
      }
      if (preservePageLabels && labelPairs.size() > 0) {
        output.rootCatalog().pdfRepresentation().put(CraftPdfName('PageLabels'),
            CraftPdfDictionary()..put(CraftPdfName('Nums'), labelPairs));
      }
      await output.close();
      return bytes.takeBytes();
    } finally {
      for (final doc in opened) {
        await doc.close();
      }
    }
  }

  static Future<Map<int, CraftPdfDictionary>> _pageLabels(
      CraftPdfDocument source) async {
    final root = await source
        .rootCatalog()
        .pdfRepresentation()
        .dictionaryEntry(CraftPdfName('PageLabels'));
    final result = <int, CraftPdfDictionary>{};
    final visited = HashSet<CraftPdfDictionary>.identity();
    Future<void> visit(CraftPdfDictionary node) async {
      if (!visited.add(node) || visited.length > 10000)
        throw FormatException('Invalid page label tree.');
      for (final entry in await node.entrySet())
        if (!const {'Nums', 'Kids', 'Limits'}.contains(entry.key.getValue()))
          throw UnsupportedError('Unknown page label tree entry.');
      final pairs = await node.arrayEntry(CraftPdfName('Nums'));
      if (pairs != null) {
        if (pairs.size().isOdd)
          throw FormatException('Page label number tree requires pairs.');
        for (var i = 0; i < pairs.size(); i += 2) {
          final index = await pairs.numberEntry(i),
              rule = await pairs.dictionaryEntry(i + 1);
          if (index == null ||
              index.doubleValue() != index.intValue() ||
              index.intValue() < 0 ||
              rule == null ||
              result.containsKey(index.intValue()))
            throw FormatException('Invalid page label rule.');
          for (final entry in await rule.entrySet())
            if (!const {'Type', 'S', 'P', 'St'}.contains(entry.key.getValue()))
              throw UnsupportedError('Unknown page label rule entry.');
          for (final entry in await rule.entrySet()) {
            final value = await rule.get(entry.key, true);
            final key = entry.key.getValue();
            if ((key == 'P' && value is! CraftPdfString) ||
                ((key == 'S' || key == 'Type') && value is! CraftPdfName) ||
                (key == 'St' && value is! CraftPdfNumber))
              throw FormatException('Invalid page label value type.');
          }
          final style = await rule.nameEntry(CraftPdfName('S'));
          if (style != null &&
              !const {'D', 'R', 'r', 'A', 'a'}.contains(style.getValue()))
            throw FormatException('Unknown page numbering style.');
          final start = await rule.numberEntry(CraftPdfName('St'));
          if (start != null &&
              (start.intValue() < 1 || start.doubleValue() != start.intValue()))
            throw FormatException('Invalid page label starting number.');
          result[index.intValue()] = rule;
        }
      }
      final kids = await node.arrayEntry(CraftPdfName('Kids'));
      if (kids != null)
        for (var i = 0; i < kids.size(); i++) {
          final child = await kids.dictionaryEntry(i);
          if (child == null) throw FormatException('Invalid label tree child.');
          await visit(child);
        }
    }

    if (root != null) await visit(root);
    return result;
  }

  static Future<Map<CraftPdfObject, CraftPdfObject>> _importLayers(
      CraftPdfDocument source, CraftPdfDocument output) async {
    final root = await source
        .rootCatalog()
        .pdfRepresentation()
        .dictionaryEntry(CraftPdfName('OCProperties'));
    if (root == null) return <CraftPdfObject, CraftPdfObject>{};
    for (final entry in await root.entrySet())
      if (!const {'OCGs', 'D'}.contains(entry.key.getValue()))
        throw UnsupportedError(
            'Alternate layer configurations are not supported.');
    final groups = await root.arrayEntry(CraftPdfName('OCGs'));
    if (groups == null) throw FormatException('Layer catalog requires OCGs.');
    final copier = _PageGraphCopy(output, protectPageReferences: true);
    final originals = <CraftPdfDictionary>[];
    for (var i = 0; i < groups.size(); i++) {
      final group = await groups.dictionaryEntry(i);
      if (group == null ||
          (await group.nameEntry(CraftPdfName.type))?.getValue() != 'OCG')
        throw FormatException('Invalid layer group.');
      for (final entry in await group.entrySet()) {
        if (!const {'Type', 'Name', 'Intent', 'Usage'}
            .contains(entry.key.getValue()))
          throw UnsupportedError('Unsupported layer group entry.');
      }
      originals.add(group);
      await copier.copy(group);
    }
    final destination = output.rootCatalog().pdfRepresentation();
    var merged =
        await destination.dictionaryEntry(CraftPdfName('OCProperties'));
    if (merged == null) {
      merged = CraftPdfDictionary()
        ..put(CraftPdfName('OCGs'), CraftPdfArray())
        ..put(
            CraftPdfName('D'),
            CraftPdfDictionary()
              ..put(CraftPdfName('BaseState'), CraftPdfName('ON'))
              ..put(CraftPdfName('OFF'), CraftPdfArray()));
      destination.put(CraftPdfName('OCProperties'), merged);
    }
    final targetGroups = (await merged.arrayEntry(CraftPdfName('OCGs')))!;
    for (final group in originals) {
      targetGroups.add(copier.copies[group]!);
    }
    final config = await root.dictionaryEntry(CraftPdfName('D'));
    final targetConfig = (await merged.dictionaryEntry(CraftPdfName('D')))!;
    if (config != null) {
      for (final entry in await config.entrySet())
        if (!const {
          'Name',
          'Creator',
          'BaseState',
          'ON',
          'OFF',
          'Order',
          'RBGroups',
          'Locked',
          'ListMode',
          'Intent'
        }.contains(entry.key.getValue()))
          throw UnsupportedError(
              'Layer configuration requires unsupported automatic rules.');
      final state =
          (await config.nameEntry(CraftPdfName('BaseState')))?.getValue() ??
              'ON';
      if (state != 'ON' && state != 'OFF')
        throw UnsupportedError('Unchanged layer base state cannot be merged.');
      final disabled = HashSet<CraftPdfDictionary>.identity();
      if (state == 'OFF') disabled.addAll(originals);
      for (final key in ['ON', 'OFF']) {
        final list = await config.arrayEntry(CraftPdfName(key));
        if (list != null)
          for (var i = 0; i < list.size(); i++) {
            final group = await list.dictionaryEntry(i);
            if (group == null || !originals.contains(group))
              throw FormatException('Layer state references a foreign group.');
            if (key == 'ON')
              disabled.remove(group);
            else
              disabled.add(group);
          }
      }
      final off = (await targetConfig.arrayEntry(CraftPdfName('OFF')))!;
      for (final group in disabled) {
        off.add(copier.copies[group]!);
      }
      final checked = HashSet<CraftPdfObject>.identity();
      Future<void> validateOrder(CraftPdfObject object) async {
        if (object is CraftPdfIndirectReference) {
          final direct = await object.targetObject(true);
          if (direct == null)
            throw FormatException('Unresolved layer order reference.');
          await validateOrder(direct);
          return;
        }
        if (!checked.add(object)) return;
        if (object is CraftPdfDictionary) {
          if (!originals.contains(object))
            throw FormatException('Layer order references a foreign group.');
        } else if (object is CraftPdfArray) {
          for (var i = 0; i < object.size(); i++) {
            final value = await object.get(i, true);
            if (value != null) await validateOrder(value);
          }
        } else if (object is! CraftPdfString)
          throw FormatException('Invalid layer order value.');
      }

      for (final key in ['Order', 'RBGroups', 'Locked']) {
        final value = await config.arrayEntry(CraftPdfName(key));
        if (value == null) continue;
        await validateOrder(value);
        var target = await targetConfig.arrayEntry(CraftPdfName(key));
        if (target == null) {
          target = CraftPdfArray();
          targetConfig.put(CraftPdfName(key), target);
        }
        for (var i = 0; i < value.size(); i++) {
          final item = await value.get(i, true);
          if (item != null) target.add(await copier.copy(item));
        }
      }
    }
    return copier.copies;
  }

  static Future<void> _flattenAnnotations(
      CraftPdfPage page,
      CraftPdfDictionary target,
      _PageGraphCopy copier,
      CraftPdfDocument output,
      PdfMergeSignaturePolicy signaturePolicy) async {
    final annotations =
        await page.pdfRepresentation().arrayEntry(CraftPdfName.annots);
    if (annotations == null) return;
    final resources = (await target.dictionaryEntry(CraftPdfName.resources))!;
    final forms = (await resources.dictionaryEntry(CraftPdfName.xObject))!;
    final commands = StringBuffer('q /Page Do Q\n');
    Future<List<double>> numbers(CraftPdfArray? array, int count) async {
      if (array == null || array.size() != count)
        throw FormatException('Invalid annotation appearance geometry.');
      final result = <double>[];
      for (var i = 0; i < count; i++) {
        final value = await array.numberEntry(i);
        if (value == null || !value.doubleValue().isFinite)
          throw FormatException('Invalid appearance coordinate.');
        result.add(value.doubleValue());
      }
      return result;
    }

    for (var i = 0; i < annotations.size(); i++) {
      final annotation = await annotations.dictionaryEntry(i);
      if (annotation == null) throw FormatException('Invalid annotation.');
      CraftPdfDictionary? field = annotation;
      final ancestors = HashSet<CraftPdfDictionary>.identity();
      var signature = false;
      while (field != null && ancestors.add(field)) {
        final type = await field.nameEntry(CraftPdfName('FT'));
        if (type != null) {
          signature = type.getValue() == 'Sig';
          break;
        }
        field = await field.dictionaryEntry(CraftPdfName.parent);
      }
      if (signature) {
        if (signaturePolicy == PdfMergeSignaturePolicy.reject ||
            signaturePolicy == PdfMergeSignaturePolicy.keepInvalid)
          throw UnsupportedError(
              'Flattening signatures requires an explicit removal policy.');
        if (signaturePolicy == PdfMergeSignaturePolicy.removeAppearance)
          continue;
      }
      final flags =
          (await annotation.numberEntry(CraftPdfName('F')))?.intValue() ?? 0;
      if ((flags & 3) != 0 || (flags & 32) != 0) continue;
      final appearance = await annotation.dictionaryEntry(CraftPdfName('AP'));
      var normal = await appearance?.get(CraftPdfName('N'), true);
      if (normal is CraftPdfDictionary && normal is! CraftPdfStream) {
        final state = await annotation.nameEntry(CraftPdfName('AS'));
        normal = state == null ? null : await normal.get(state, true);
      }
      if (normal is! CraftPdfStream)
        throw UnsupportedError(
            'Visible annotations require an existing normal appearance to flatten.');
      final rect =
          await numbers(await annotation.arrayEntry(CraftPdfName('Rect')), 4);
      final box = await numbers(await normal.arrayEntry(CraftPdfName.bBox), 4);
      final matrix = await normal.arrayEntry(CraftPdfName('Matrix'));
      final m = matrix == null
          ? <double>[1, 0, 0, 1, 0, 0]
          : await numbers(matrix, 6);
      final xs = <double>[], ys = <double>[];
      for (final x in [box[0], box[2]])
        for (final y in [box[1], box[3]]) {
          xs.add(m[0] * x + m[2] * y + m[4]);
          ys.add(m[1] * x + m[3] * y + m[5]);
        }
      xs.sort();
      ys.sort();
      final width = xs.last - xs.first, height = ys.last - ys.first;
      if (width <= 0 || height <= 0 || rect[2] <= rect[0] || rect[3] <= rect[1])
        throw FormatException('Empty annotation appearance bounds.');
      final sx = (rect[2] - rect[0]) / width, sy = (rect[3] - rect[1]) / height;
      final tx = rect[0] - sx * xs.first, ty = rect[1] - sy * ys.first;
      final name = 'Appearance$i';
      forms.put(CraftPdfName(name), await copier.copy(normal));
      String decimal(double value) {
        if (!value.isFinite)
          throw FormatException('Appearance transform is not finite.');
        return value.toStringAsFixed(16);
      }

      commands.writeln(
          'q ${decimal(sx)} 0 0 ${decimal(sy)} ${decimal(tx)} ${decimal(ty)} cm /$name Do Q');
    }
    target.put(
        CraftPdfName.contents,
        CraftPdfStream.withBytes(
            Uint8List.fromList(commands.toString().codeUnits)));
  }

  static Future<void> _resolveNames(CraftPdfDocument doc) async {
    final catalog = doc.rootCatalog().pdfRepresentation();
    final destinations = <String, CraftPdfObject>{};
    final legacy = await catalog.dictionaryEntry(CraftPdfName('Dests'));
    if (legacy != null) {
      for (final entry in await legacy.entrySet()) {
        destinations[entry.key.getValue()] = entry.value;
      }
    }
    final names = await catalog.dictionaryEntry(CraftPdfName('Names'));
    if (names != null) {
      for (final entry in await names.entrySet()) {
        if (entry.key.getValue() != 'Dests')
          throw UnsupportedError(
              'Only destination name trees may be resolved.');
      }
      final visited = HashSet<CraftPdfDictionary>.identity();
      Future<void> walk(CraftPdfDictionary node) async {
        if (!visited.add(node) || visited.length > 10000)
          throw FormatException('Cyclic destination name tree.');
        final pairs = await node.arrayEntry(CraftPdfName('Names'));
        if (pairs != null) {
          if (pairs.size().isOdd)
            throw FormatException('Destination name array must contain pairs.');
          for (var i = 0; i < pairs.size(); i += 2) {
            final key = await pairs.get(i, true),
                value = await pairs.get(i + 1, true);
            if (key is! CraftPdfString || value == null)
              throw FormatException('Invalid destination name pair.');
            destinations[key.getValue()] = value;
          }
        }
        final kids = await node.arrayEntry(CraftPdfName('Kids'));
        if (kids != null)
          for (var i = 0; i < kids.size(); i++) {
            final child = await kids.get(i, true);
            if (child is! CraftPdfDictionary)
              throw FormatException('Invalid destination tree child.');
            await walk(child);
          }
      }

      final tree = await names.dictionaryEntry(CraftPdfName('Dests'));
      if (tree != null) await walk(tree);
    }
    Future<CraftPdfObject> resolve(CraftPdfObject object) async {
      final seen = <String>{};
      final objects = HashSet<CraftPdfObject>.identity();
      var current = object;
      while (true) {
        if (!objects.add(current))
          throw FormatException('Cyclic destination object.');
        if (current is CraftPdfIndirectReference) {
          final direct = await current.targetObject(true);
          if (direct == null) throw FormatException('Unresolved destination.');
          current = direct;
          continue;
        }
        if (current is CraftPdfDictionary) {
          final value = await current.get(CraftPdfName('D'), true);
          if (value == null || identical(value, current))
            throw FormatException('Invalid destination dictionary.');
          current = value;
          continue;
        }
        if (current is CraftPdfArray) return current;
        final name = current is CraftPdfName
            ? current.getValue()
            : current is CraftPdfString
                ? current.getValue()
                : null;
        if (name == null || !seen.add(name) || !destinations.containsKey(name))
          throw FormatException('Unknown or cyclic named destination.');
        current = destinations[name]!;
      }
    }

    final visited = HashSet<CraftPdfDictionary>.identity();
    Future<void> patch(CraftPdfDictionary node) async {
      if (!visited.add(node)) return;
      final direct = await node.get(CraftPdfName('Dest'), true);
      if (direct != null) node.put(CraftPdfName('Dest'), await resolve(direct));
      final action = await node.dictionaryEntry(CraftPdfName('A'));
      if (action != null &&
          (await action.nameEntry(CraftPdfName('S')))?.getValue() == 'GoTo') {
        final target = await action.get(CraftPdfName('D'), true);
        if (target == null)
          throw FormatException('Missing local action destination.');
        action.put(CraftPdfName('D'), await resolve(target));
      }
      for (final key in ['First', 'Next']) {
        final child = await node.dictionaryEntry(CraftPdfName(key));
        if (child != null) await patch(child);
      }
    }

    final outlines = await catalog.dictionaryEntry(CraftPdfName('Outlines'));
    if (outlines != null) await patch(outlines);
    for (var p = 1; p <= doc.pageTotal(); p++) {
      final annotations = await (await doc.pageAt(p))!
          .pdfRepresentation()
          .arrayEntry(CraftPdfName.annots);
      if (annotations != null)
        for (var i = 0; i < annotations.size(); i++) {
          final annotation = await annotations.get(i, true);
          if (annotation is CraftPdfDictionary) await patch(annotation);
        }
    }
  }

  static Future<List<_OutlineEntry>> _readOutlines(
      CraftPdfDictionary catalog, List<CraftPdfPage> selection) async {
    final root = await catalog.get(CraftPdfName('Outlines'), true);
    if (root == null) return [];
    if (root is! CraftPdfDictionary || root is CraftPdfStream) {
      throw FormatException('Outline root must be a dictionary.');
    }
    for (final entry in await root.entrySet()) {
      if (!const {'Type', 'First', 'Last', 'Count'}
          .contains(entry.key.getValue())) {
        throw UnsupportedError(
            'Outline root /${entry.key.getValue()} requires reconciliation.');
      }
    }
    final selected = HashSet<CraftPdfDictionary>.identity()
      ..addAll(selection.map((page) => page.pdfRepresentation()));
    final visited = HashSet<CraftPdfDictionary>.identity();
    Future<List<_OutlineEntry>> children(
        CraftPdfDictionary parent, int depth) async {
      if (depth > 128)
        throw FormatException('Outline hierarchy exceeds 128 levels.');
      final entries = <_OutlineEntry>[];
      var object = await parent.get(CraftPdfName('First'), true);
      CraftPdfDictionary? last;
      while (object != null) {
        if (object is! CraftPdfDictionary ||
            object is CraftPdfStream ||
            !visited.add(object) ||
            visited.length > 10000) {
          throw FormatException(
              'Outline hierarchy contains an invalid, repeated or excessive node.');
        }
        final owner = await object.get(CraftPdfName.parent, true);
        final previous = await object.get(CraftPdfName('Prev'), true);
        if ((owner != null && !identical(owner, parent)) ||
            (previous != null && !identical(previous, last))) {
          throw FormatException(
              'Outline parent or previous-sibling reference is inconsistent.');
        }
        final title = await object.get(CraftPdfName('Title'), true);
        if (title is! CraftPdfString)
          throw FormatException('Outline title must be a text string.');
        for (final entry in await object.entrySet()) {
          if (!const {
            'Title',
            'Parent',
            'Prev',
            'Next',
            'First',
            'Last',
            'Count',
            'Dest',
            'A',
            'C',
            'F'
          }.contains(entry.key.getValue())) {
            throw UnsupportedError(
                'Outline entry /${entry.key.getValue()} requires reconciliation.');
          }
        }
        var destination = await object.get(CraftPdfName('Dest'), true);
        final action = await object.get(CraftPdfName('A'), true);
        if (action != null) {
          if (destination != null ||
              action is! CraftPdfDictionary ||
              action is CraftPdfStream ||
              (await action.nameEntry(CraftPdfName('S')))?.getValue() !=
                  'GoTo') {
            throw UnsupportedError(
                'Only a single local GoTo outline action is supported.');
          }
          for (final entry in await action.entrySet()) {
            if (!const {'Type', 'S', 'D'}.contains(entry.key.getValue())) {
              throw UnsupportedError(
                  'Outline action /${entry.key.getValue()} is unsupported.');
            }
          }
          destination = await action.get(CraftPdfName('D'), true);
          if (destination == null)
            throw FormatException('Outline GoTo action has no destination.');
        }
        CraftPdfDictionary? target;
        final parameters = <CraftPdfObject>[];
        if (destination != null) {
          if (destination is! CraftPdfArray || destination.size() < 2) {
            throw UnsupportedError(
                'Outline destinations must be explicit local arrays.');
          }
          final page = await destination.get(0, true);
          if (page is! CraftPdfDictionary || !selected.contains(page)) {
            throw UnsupportedError(
                'Outline destination targets an omitted or foreign page.');
          }
          target = page;
          final mode = await destination.get(1, true);
          const lengths = {
            'XYZ': 5,
            'Fit': 2,
            'FitB': 2,
            'FitH': 3,
            'FitV': 3,
            'FitBH': 3,
            'FitBV': 3,
            'FitR': 6
          };
          if (mode is! CraftPdfName ||
              lengths[mode.getValue()] != destination.size()) {
            throw FormatException(
                'Outline destination has invalid fit mode or parameter count.');
          }
          parameters.add(mode);
          for (var index = 2; index < destination.size(); index++) {
            final value = await destination.get(index, true);
            if (value == null ||
                (value is! CraftPdfNumber &&
                    !(value.objectKind() == PdfObjectType.nullType &&
                        mode.getValue() != 'FitR'))) {
              throw FormatException(
                  'Outline coordinates must be numbers or permitted nulls.');
            }
            parameters.add(value);
          }
        }
        final appearance = <CraftPdfName, CraftPdfObject>{};
        for (final key in ['C', 'F']) {
          final value = await object.get(CraftPdfName(key), true);
          if (value == null) continue;
          if (key == 'F' && value is! CraftPdfNumber)
            throw FormatException('Outline style flags must be numeric.');
          if (key == 'C') {
            if (value is! CraftPdfArray || value.size() != 3)
              throw FormatException('Outline color requires three components.');
            for (var index = 0; index < 3; index++) {
              if (await value.get(index, true) is! CraftPdfNumber)
                throw FormatException(
                    'Outline color components must be numeric.');
            }
          }
          appearance[CraftPdfName(key)] = value;
        }
        final count = await object.get(CraftPdfName('Count'), true);
        if (count != null && count is! CraftPdfNumber)
          throw FormatException('Outline count must be numeric.');
        entries.add(_OutlineEntry(
            title,
            target,
            parameters,
            appearance,
            count is! CraftPdfNumber || count.intValue() >= 0,
            await children(object, depth + 1)));
        last = object;
        object = await object.get(CraftPdfName('Next'), true);
      }
      final expectedLast = await parent.get(CraftPdfName('Last'), true);
      if (expectedLast != null && !identical(last, expectedLast)) {
        throw FormatException('Outline final sibling does not match /Last.');
      }
      return entries;
    }

    return children(root, 0);
  }

  static Future<List<CraftPdfDictionary>> _writeOutlineEntries(
      List<_OutlineEntry> entries,
      CraftPdfDocument document,
      Map<CraftPdfDictionary, CraftPdfDictionary> pages) async {
    final result = <CraftPdfDictionary>[];
    final copier = _PageGraphCopy(document, protectPageReferences: true);
    for (final entry in entries) {
      final node = CraftPdfDictionary()
        ..attachToDocument(document)
        ..put(CraftPdfName('Title'), entry.title.clone());
      if (entry.target != null) {
        final target = pages[entry.target];
        if (target == null)
          throw StateError('Validated outline target was not imported.');
        final destination = CraftPdfArray.withObject(target);
        for (final value in entry.parameters) destination.add(value.clone());
        node.put(CraftPdfName('Dest'), destination);
      }
      for (final appearance in entry.appearance.entries) {
        node.put(appearance.key, await copier.copy(appearance.value));
      }
      final nested =
          await _writeOutlineEntries(entry.children, document, pages);
      if (nested.isNotEmpty) {
        _linkOutlineSiblings(node, nested);
        final visible = await _visibleOutlineCount(nested);
        node.put(CraftPdfName('Count'),
            CraftPdfNumber.fromInt(entry.open ? visible : -visible));
      }
      result.add(node);
    }
    return result;
  }

  static void _linkOutlineSiblings(
      CraftPdfDictionary parent, List<CraftPdfDictionary> nodes) {
    parent.put(CraftPdfName('First'), nodes.first);
    parent.put(CraftPdfName('Last'), nodes.last);
    for (var index = 0; index < nodes.length; index++) {
      nodes[index].put(CraftPdfName.parent, parent);
      if (index > 0) nodes[index].put(CraftPdfName('Prev'), nodes[index - 1]);
      if (index + 1 < nodes.length)
        nodes[index].put(CraftPdfName('Next'), nodes[index + 1]);
    }
  }

  static Future<int> _visibleOutlineCount(
      List<CraftPdfDictionary> nodes) async {
    var result = nodes.length;
    for (final node in nodes) {
      final count = await node.numberEntry(CraftPdfName('Count'));
      if (count != null && count.intValue() > 0) result += count.intValue();
    }
    return result;
  }

  static Future<void> _validateAnnotations(CraftPdfPage page,
      {bool allowLocalLinks = false, bool allowWidgets = false}) async {
    final pageObject = page.pdfRepresentation();
    final value = await pageObject.get(CraftPdfName.annots, true);
    if (value == null) return;
    if (value is! CraftPdfArray)
      throw FormatException('Page annotations must be an array.');
    final annotations = HashSet<CraftPdfDictionary>.identity();
    for (var index = 0; index < value.size(); index++) {
      final entry = await value.get(index, true);
      if (entry is! CraftPdfDictionary || entry is CraftPdfStream) {
        throw FormatException('Annotation entries must be dictionaries.');
      }
      annotations.add(entry);
    }
    const supported = {
      'Text',
      'FreeText',
      'Line',
      'Square',
      'Circle',
      'Polygon',
      'PolyLine',
      'Highlight',
      'Underline',
      'Squiggly',
      'StrikeOut',
      'Stamp',
      'Caret',
      'Ink',
      'Popup',
      'Link',
    };
    for (final annotation in annotations) {
      final kind =
          (await annotation.nameEntry(CraftPdfName.subtype))?.getValue();
      if (allowWidgets && kind == 'Widget') continue;
      if (!supported.contains(kind)) {
        throw UnsupportedError(
            'Page assembly cannot import annotation subtype /$kind.');
      }
      for (final key in [
        'AA',
        if (!allowLocalLinks) 'Dest',
        'StructParent',
        'OC'
      ]) {
        if (annotation.containsKey(CraftPdfName(key))) {
          throw UnsupportedError(
              'Page assembly cannot reconcile annotation /$key.');
        }
      }
      final owner = await annotation.get(CraftPdfName('P'), true);
      if (owner != null && !identical(owner, pageObject)) {
        throw UnsupportedError(
            'Annotation page reference points outside its containing page.');
      }
      for (final key in ['Popup', 'Parent', 'IRT']) {
        final target = await annotation.get(CraftPdfName(key), true);
        if (target == null) continue;
        if (target is! CraftPdfDictionary || !annotations.contains(target)) {
          throw UnsupportedError(
              'Annotation /$key relationship must stay on the selected page.');
        }
        if (key == 'Parent' && kind != 'Popup') {
          throw UnsupportedError(
              'Only popup annotations may carry a /Parent relationship.');
        }
        if (key == 'Popup' &&
            (await target.nameEntry(CraftPdfName.subtype))?.getValue() !=
                'Popup') {
          throw FormatException(
              'Annotation popup relationship does not target a popup.');
        }
      }
      final action = await annotation.get(CraftPdfName('A'), true);
      if (allowLocalLinks &&
          kind == 'Link' &&
          action is CraftPdfDictionary &&
          (await action.nameEntry(CraftPdfName('S')))?.getValue() == 'GoTo') {
        for (final entry in await action.entrySet()) {
          if (!const {'Type', 'S', 'D'}.contains(entry.key.getValue())) {
            throw UnsupportedError('Local link action contains extra actions.');
          }
        }
        if (await action.get(CraftPdfName('D'), true) is! CraftPdfArray) {
          throw FormatException('Local link requires an explicit destination.');
        }
        continue;
      }
      if (action != null) {
        if (kind != 'Link' ||
            action is! CraftPdfDictionary ||
            action is CraftPdfStream ||
            (await action.nameEntry(CraftPdfName('S')))?.getValue() != 'URI') {
          throw UnsupportedError(
              'Only URI actions on link annotations can be imported.');
        }
        for (final entry in await action.entrySet()) {
          if (!const {'Type', 'S', 'URI', 'IsMap'}
              .contains(entry.key.getValue())) {
            throw UnsupportedError(
                'URI action contains an unsupported /${entry.key.getValue()} entry.');
          }
        }
        if (await action.stringEntry(CraftPdfName('URI')) == null) {
          throw FormatException('URI action must contain a URI string.');
        }
      }
    }
  }
}

class _PageGraphCopy {
  final CraftPdfDocument destination;
  final copies = HashMap<CraftPdfObject, CraftPdfObject>.identity();
  final bool protectPageReferences;
  _PageGraphCopy(this.destination, {this.protectPageReferences = false});

  Future<CraftPdfObject> copy(CraftPdfObject object) async {
    if (object is CraftPdfIndirectReference) {
      final target = await object.targetObject(true);
      if (target == null) throw FormatException('Unresolved PDF reference.');
      return copy(target);
    }
    final previous = copies[object];
    if (previous != null) return previous;
    if (object is CraftPdfDictionary) {
      if (protectPageReferences) {
        final type = (await object.nameEntry(CraftPdfName.type))?.getValue();
        if (const {'Page', 'Pages', 'Catalog'}.contains(type)) {
          throw UnsupportedError(
              'Imported graph references an unrelated document structure /$type.');
        }
      }
      final CraftPdfDictionary result;
      if (object is CraftPdfStream) {
        // Preserve encoded bytes and their matching filter dictionaries.
        result = CraftPdfStream.withBytes(await object.getBytes(false), 0);
      } else {
        result = CraftPdfDictionary();
      }
      copies[object] = result;
      // Indirect containers preserve cycles and sharing without recursion
      // during serialization, even when a source container was direct.
      result.attachToDocument(destination);
      for (final entry in await object.entrySet()) {
        if (object is CraftPdfStream && entry.key == CraftPdfName.length)
          continue;
        result.put(entry.key, await copy(entry.value));
      }
      return result;
    }
    if (object is CraftPdfArray) {
      final result = CraftPdfArray();
      copies[object] = result;
      result.attachToDocument(destination);
      for (var i = 0; i < object.size(); i++) {
        final value = await object.get(i, false);
        if (value == null) throw FormatException('Missing PDF array item.');
        result.add(await copy(value));
      }
      return result;
    }
    final result = object.clone();
    copies[object] = result;
    return result;
  }
}

class _OutlineEntry {
  final CraftPdfString title;
  final CraftPdfDictionary? target;
  final List<CraftPdfObject> parameters;
  final Map<CraftPdfName, CraftPdfObject> appearance;
  final bool open;
  final List<_OutlineEntry> children;
  _OutlineEntry(this.title, this.target, this.parameters, this.appearance,
      this.open, this.children);
}
