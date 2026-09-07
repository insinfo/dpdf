import 'dart:collection';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_page.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/pdf_stream.dart';

/// Existing signatures cannot authenticate newly assembled document bytes.
enum PdfMergeSignaturePolicy {
  reject,
  removeKeepAppearance,
  removeAppearance,
  keepInvalid
}

class PdfFormMerge {
  static Future<PdfFormMergePlan> prepare(
      CraftPdfDocument source, List<CraftPdfPage> selected,
      {PdfMergeSignaturePolicy signaturePolicy =
          PdfMergeSignaturePolicy.reject}) async {
    final pages = HashSet<CraftPdfDictionary>.identity();
    final widgetPages =
        HashMap<CraftPdfDictionary, CraftPdfDictionary>.identity();
    for (final page in selected) {
      final dictionary = page.pdfRepresentation();
      pages.add(dictionary);
      final annotations = await dictionary.arrayEntry(CraftPdfName.annots);
      if (annotations != null) {
        for (var i = 0; i < annotations.size(); i++) {
          final widget = await annotations.dictionaryEntry(i);
          if (widget != null &&
              await widget.nameEntry(CraftPdfName.subtype) ==
                  CraftPdfName.widget) {
            widgetPages[widget] = dictionary;
          }
        }
      }
    }
    final form = await source
        .rootCatalog()
        .pdfRepresentation()
        .dictionaryEntry(CraftPdfName.acroForm);
    if (form == null) {
      if (widgetPages.isNotEmpty) {
        throw FormatException('Page widgets have no AcroForm hierarchy');
      }
      return PdfFormMergePlan._(null, [], widgetPages, signaturePolicy);
    }
    for (final key in ['XFA', 'CO', 'AA']) {
      if (form.containsKey(CraftPdfName(key))) {
        throw UnsupportedError(
            'AcroForm /$key requires specialized merge support');
      }
    }
    final roots = await form.arrayEntry(CraftPdfName.fields);
    final seen = HashSet<CraftPdfDictionary>.identity();
    final accounted = HashSet<CraftPdfDictionary>.identity();
    Future<_FieldNode> visit(
        CraftPdfDictionary dictionary, String? inheritedType, int depth) async {
      if (depth > 128 || !seen.add(dictionary)) {
        throw FormatException('Cyclic or shared AcroForm field hierarchy');
      }
      for (final key in ['A', 'AA']) {
        if (dictionary.containsKey(CraftPdfName(key))) {
          throw UnsupportedError('Field actions require merge reconciliation');
        }
      }
      final type = (await dictionary.nameEntry(CraftPdfName.ft))?.getValue() ??
          inheritedType;
      final signed =
          type == 'Sig' && await dictionary.get(CraftPdfName.v, true) != null;
      if (signed && signaturePolicy == PdfMergeSignaturePolicy.reject) {
        throw UnsupportedError(
            'Merging would invalidate an existing PDF signature');
      }
      final children = <_FieldNode>[];
      final widgets = <CraftPdfDictionary>[];
      final kids = await dictionary.arrayEntry(CraftPdfName.kids);
      if (kids != null) {
        for (var i = 0; i < kids.size(); i++) {
          final child = await kids.dictionaryEntry(i);
          if (child == null) {
            throw FormatException('AcroForm child must be a dictionary');
          }
          if (await child.nameEntry(CraftPdfName.subtype) ==
                  CraftPdfName.widget &&
              !child.containsKey(CraftPdfName.t)) {
            if (widgetPages.containsKey(child)) {
              widgets.add(child);
              accounted.add(child);
            }
          } else {
            children.add(await visit(child, type, depth + 1));
          }
        }
      }
      if (await dictionary.nameEntry(CraftPdfName.subtype) ==
              CraftPdfName.widget &&
          widgetPages.containsKey(dictionary)) {
        widgets.add(dictionary);
        accounted.add(dictionary);
      }
      final hasAnyWidgets = await dictionary.nameEntry(CraftPdfName.subtype) ==
              CraftPdfName.widget ||
          (kids != null && children.isEmpty);
      return _FieldNode(
          dictionary,
          children,
          widgets,
          signed,
          children.isNotEmpty
              ? children.any((child) => child.retained)
              : !hasAnyWidgets || widgets.isNotEmpty);
    }

    final nodes = <_FieldNode>[];
    if (roots != null) {
      for (var i = 0; i < roots.size(); i++) {
        final field = await roots.dictionaryEntry(i);
        if (field == null) {
          throw FormatException('AcroForm root must be a dictionary');
        }
        nodes.add(await visit(field, null, 0));
      }
    }
    if (widgetPages.keys.any((widget) => !accounted.contains(widget))) {
      throw FormatException('Page widget is absent from AcroForm hierarchy');
    }
    return PdfFormMergePlan._(form, nodes, widgetPages, signaturePolicy);
  }
}

class _FieldNode {
  final CraftPdfDictionary source;
  final List<_FieldNode> children;
  final List<CraftPdfDictionary> widgets;
  final bool signed;
  final bool retained;
  _FieldNode(
      this.source, this.children, this.widgets, this.signed, this.retained);
}

class PdfFormMergePlan {
  final CraftPdfDictionary? _form;
  final List<_FieldNode> _roots;
  final Map<CraftPdfDictionary, CraftPdfDictionary> _widgetPages;
  final PdfMergeSignaturePolicy _policy;
  PdfFormMergePlan._(this._form, this._roots, this._widgetPages, this._policy);

  /// Tests whether a selected widget belongs to a populated signature field.
  bool isSignedWidget(CraftPdfDictionary widget) {
    bool contains(_FieldNode node, bool inherited) {
      final signed = inherited || node.signed;
      if (signed && node.widgets.any((value) => identical(value, widget))) {
        return true;
      }
      return node.children.any((child) => contains(child, signed));
    }

    return _roots.any((node) => contains(node, false));
  }

  Future<void> importInto(
      CraftPdfDocument output,
      Map<CraftPdfDictionary, CraftPdfDictionary> targets,
      Future<CraftPdfObject> Function(CraftPdfObject) copy,
      {Map<CraftPdfDictionary, List<CraftPdfDictionary>>?
          repeatedTargets}) async {
    if (_form == null) return;
    final catalog = output.rootCatalog().pdfRepresentation();
    var destination = await catalog.dictionaryEntry(CraftPdfName.acroForm);
    if (destination == null) {
      destination = CraftPdfDictionary()..attachToDocument(output);
      catalog.put(CraftPdfName.acroForm, destination);
    }
    var fields = await destination.arrayEntry(CraftPdfName.fields);
    if (fields == null) {
      fields = CraftPdfArray();
      destination.put(CraftPdfName.fields, fields);
    }
    final usedNames = <String>{};
    Future<void> collectNames(CraftPdfDictionary node, String prefix,
        Set<CraftPdfDictionary> seen) async {
      if (!seen.add(node)) {
        throw FormatException('Output form hierarchy contains a cycle');
      }
      final partial =
          (await node.stringEntry(CraftPdfName.t))?.decodeMappingText();
      final full = partial == null
          ? prefix
          : prefix.isEmpty
              ? partial
              : '$prefix.$partial';
      if (partial != null) usedNames.add(full);
      final kids = await node.arrayEntry(CraftPdfName.kids);
      if (kids != null) {
        for (var i = 0; i < kids.size(); i++) {
          final child = await kids.dictionaryEntry(i);
          if (child != null && child.containsKey(CraftPdfName.t)) {
            await collectNames(child, full, seen);
          }
        }
      }
    }

    for (var i = 0; i < fields.size(); i++) {
      final field = await fields.dictionaryEntry(i);
      if (field != null) {
        await collectNames(field, '', HashSet<CraftPdfDictionary>.identity());
      }
    }
    Future<Set<String>> incomingNames(_FieldNode node, String name) async {
      final result = <String>{name};
      for (final child in node.children) {
        if (!child.retained) continue;
        final partial = (await child.source.stringEntry(CraftPdfName.t))
            ?.decodeMappingText();
        result.addAll(await incomingNames(
            child, partial == null ? name : '$name.$partial'));
      }
      return result;
    }

    final resourceNames = <String, String>{};
    final resources = await _form.dictionaryEntry(CraftPdfName.dr);
    if (resources != null) {
      var destResources = await destination.dictionaryEntry(CraftPdfName.dr);
      if (destResources == null) {
        destResources = CraftPdfDictionary();
        destination.put(CraftPdfName.dr, destResources);
      }
      for (final category in await resources.entrySet()) {
        final sourceGroup = await resources.dictionaryEntry(category.key);
        if (sourceGroup == null) {
          if (category.key.getValue() == 'ProcSet') {
            final value = await resources.arrayEntry(category.key);
            if (value == null) {
              throw FormatException('AcroForm ProcSet must be an array');
            }
            var combined = await destResources.arrayEntry(category.key);
            if (combined == null) {
              combined = CraftPdfArray();
              destResources.put(category.key, combined);
            }
            for (var i = 0; i < value.size(); i++) {
              final item = await value.get(i);
              if (item != null) combined.add(await copy(item));
            }
            continue;
          }
          throw FormatException(
              'AcroForm resource category must be a dictionary');
        }
        var group = await destResources.dictionaryEntry(category.key);
        if (group == null) {
          group = CraftPdfDictionary();
          destResources.put(category.key, group);
        }
        for (final entry in await sourceGroup.entrySet()) {
          final original = entry.key.getValue();
          var name = original;
          var suffix = 2;
          while (group.containsKey(CraftPdfName(name))) {
            name = '${original}_${suffix++}';
          }
          group.put(CraftPdfName(name), await copy(entry.value));
          if (category.key.getValue() == 'Font') resourceNames[original] = name;
        }
      }
    }
    String rewriteAppearance(String value) =>
        value.replaceAllMapped(RegExp(r'/([^\s/<>\[\](){}%]+)'), (match) {
          final name = match.group(1)!.replaceAllMapped(
              RegExp(r'#([0-9a-fA-F]{2})'),
              (escape) =>
                  String.fromCharCode(int.parse(escape.group(1)!, radix: 16)));
          final replacement = resourceNames[name];
          if (replacement == null) return match.group(0)!;
          final encoded = CraftPdfName(replacement).toString();
          return encoded.startsWith('/') ? encoded : '/$encoded';
        });
    Future<void> copyEntries(CraftPdfDictionary from, CraftPdfDictionary to,
        Set<String> excluded) async {
      for (final entry in await from.entrySet()) {
        if (excluded.contains(entry.key.getValue())) continue;
        if (entry.key == CraftPdfName.da) {
          final text = await from.stringEntry(entry.key);
          if (text != null) {
            to.put(entry.key,
                CraftPdfString(rewriteAppearance(text.decodeMappingText())));
            continue;
          }
        }
        to.put(entry.key, await copy(entry.value));
      }
    }

    Future<List<CraftPdfDictionary>> attachWidget(
        CraftPdfDictionary source, CraftPdfDictionary target) async {
      final sourcePage = _widgetPages[source];
      final first = targets[sourcePage];
      final pages = repeatedTargets?[sourcePage] ??
          (first == null ? <CraftPdfDictionary>[] : [first]);
      if (pages.isEmpty) throw StateError('Merged widget has no target page');
      final instances = <CraftPdfDictionary>[];
      for (final page in pages) {
        CraftPdfDictionary instance;
        if (instances.isEmpty) {
          instance = target;
        } else {
          instance = CraftPdfDictionary()..attachToDocument(output);
          for (final entry in await target.entrySet()) {
            if (entry.key != CraftPdfName.p) {
              instance.put(entry.key, entry.value);
            }
          }
        }
        instance.put(CraftPdfName.p, page);
        var annotations = await page.arrayEntry(CraftPdfName.annots);
        if (annotations == null) {
          annotations = CraftPdfArray();
          page.put(CraftPdfName.annots, annotations);
        }
        annotations.add(instance);
        instances.add(instance);
      }
      return instances;
    }

    Future<void> preserveStamp(CraftPdfDictionary widget) async {
      final appearance = await widget.dictionaryEntry(CraftPdfName.ap);
      var normal = await appearance?.get(CraftPdfName.n, true);
      if (normal is CraftPdfDictionary && normal is! CraftPdfStream) {
        final state = await widget.nameEntry(CraftPdfName.as);
        normal = state == null ? null : await normal.get(state, true);
      }
      if (normal is! CraftPdfStream) {
        throw UnsupportedError(
            'Signature appearance cannot be preserved without a normal appearance stream');
      }
      final stamp = CraftPdfDictionary()..attachToDocument(output);
      await copyEntries(widget, stamp, {
        'Parent',
        'P',
        'Kids',
        'FT',
        'T',
        'TU',
        'TM',
        'Ff',
        'V',
        'DV',
        'DA',
        'AP',
        'AS',
        'A',
        'AA'
      });
      stamp.put(CraftPdfName.subtype, CraftPdfName('Stamp'));
      stamp.put(CraftPdfName.ap,
          CraftPdfDictionary()..put(CraftPdfName.n, await copy(normal)));
      await attachWidget(widget, stamp);
    }

    Future<CraftPdfDictionary?> clone(
        _FieldNode node, CraftPdfDictionary? parent) async {
      if (!node.retained) return null;
      if (node.signed && _policy != PdfMergeSignaturePolicy.keepInvalid) {
        if (_policy == PdfMergeSignaturePolicy.removeKeepAppearance) {
          Future<void> stamps(_FieldNode branch) async {
            for (final widget in branch.widgets) {
              await preserveStamp(widget);
            }
            for (final child in branch.children) {
              await stamps(child);
            }
          }

          await stamps(node);
        }
        return null;
      }
      final field = CraftPdfDictionary()..attachToDocument(output);
      await copyEntries(node.source, field,
          {'Parent', 'Kids', 'P', 'Subtype', 'Rect', 'AP', 'AS', 'V'});
      // Value cloning is deliberately deferred until after signature policy filtering.
      final value = await node.source.get(CraftPdfName.v, true);
      if (value != null) field.put(CraftPdfName.v, await copy(value));
      if (parent != null) field.put(CraftPdfName.parent, parent);
      if (parent == null) {
        final original = (await node.source.stringEntry(CraftPdfName.t))
            ?.decodeMappingText();
        if (original != null) {
          var name = original;
          var suffix = 2;
          var names = await incomingNames(node, name);
          while (names.any(usedNames.contains)) {
            name = '${original}_${suffix++}';
            names = await incomingNames(node, name);
          }
          usedNames.addAll(names);
          field.put(CraftPdfName.t, CraftPdfString(name));
        }
        if (!field.containsKey(CraftPdfName.da)) {
          final da = await _form.stringEntry(CraftPdfName.da);
          if (da != null) {
            field.put(CraftPdfName.da,
                CraftPdfString(rewriteAppearance(da.decodeMappingText())));
          }
        }
      }
      final kids = CraftPdfArray();
      for (final child in node.children) {
        final copied = await clone(child, field);
        if (copied != null) kids.add(copied);
      }
      for (final widget in node.widgets) {
        final target = CraftPdfDictionary()..attachToDocument(output);
        await copyEntries(widget, target, {
          'Parent',
          'P',
          'Kids',
          'FT',
          'T',
          'TU',
          'TM',
          'Ff',
          'V',
          'DV',
          'A',
          'AA'
        });
        target.put(CraftPdfName.parent, field);
        for (final instance in await attachWidget(widget, target)) {
          kids.add(instance);
        }
      }
      if (kids.size() > 0) field.put(CraftPdfName.kids, kids);
      return field;
    }

    for (final root in _roots) {
      final cloned = await clone(root, null);
      if (cloned != null) fields.add(cloned);
    }
  }
}
