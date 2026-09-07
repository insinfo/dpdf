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
      PdfDocument source, List<PdfPage> selected,
      {PdfMergeSignaturePolicy signaturePolicy =
          PdfMergeSignaturePolicy.reject}) async {
    final pages = HashSet<PdfDictionary>.identity();
    final widgetPages = HashMap<PdfDictionary, PdfDictionary>.identity();
    for (final page in selected) {
      final dictionary = page.pdfRepresentation();
      pages.add(dictionary);
      final annotations = await dictionary.arrayEntry(PdfName.annots);
      if (annotations != null) {
        for (var i = 0; i < annotations.size(); i++) {
          final widget = await annotations.dictionaryEntry(i);
          if (widget != null &&
              await widget.nameEntry(PdfName.subtype) == PdfName.widget) {
            widgetPages[widget] = dictionary;
          }
        }
      }
    }
    final form = await source
        .rootCatalog()
        .pdfRepresentation()
        .dictionaryEntry(PdfName.acroForm);
    if (form == null) {
      if (widgetPages.isNotEmpty) {
        throw FormatException('Page widgets have no AcroForm hierarchy');
      }
      return PdfFormMergePlan._(null, [], widgetPages, signaturePolicy);
    }
    for (final key in ['XFA', 'CO', 'AA']) {
      if (form.containsKey(PdfName(key))) {
        throw UnsupportedError(
            'AcroForm /$key requires specialized merge support');
      }
    }
    final roots = await form.arrayEntry(PdfName.fields);
    final seen = HashSet<PdfDictionary>.identity();
    final accounted = HashSet<PdfDictionary>.identity();
    Future<_FieldNode> visit(
        PdfDictionary dictionary, String? inheritedType, int depth) async {
      if (depth > 128 || !seen.add(dictionary)) {
        throw FormatException('Cyclic or shared AcroForm field hierarchy');
      }
      for (final key in ['A', 'AA']) {
        if (dictionary.containsKey(PdfName(key))) {
          throw UnsupportedError('Field actions require merge reconciliation');
        }
      }
      final type =
          (await dictionary.nameEntry(PdfName.ft))?.getValue() ?? inheritedType;
      final signed =
          type == 'Sig' && await dictionary.get(PdfName.v, true) != null;
      if (signed && signaturePolicy == PdfMergeSignaturePolicy.reject) {
        throw UnsupportedError(
            'Merging would invalidate an existing PDF signature');
      }
      final children = <_FieldNode>[];
      final widgets = <PdfDictionary>[];
      final kids = await dictionary.arrayEntry(PdfName.kids);
      if (kids != null) {
        for (var i = 0; i < kids.size(); i++) {
          final child = await kids.dictionaryEntry(i);
          if (child == null) {
            throw FormatException('AcroForm child must be a dictionary');
          }
          if (await child.nameEntry(PdfName.subtype) == PdfName.widget &&
              !child.containsKey(PdfName.t)) {
            if (widgetPages.containsKey(child)) {
              widgets.add(child);
              accounted.add(child);
            }
          } else {
            children.add(await visit(child, type, depth + 1));
          }
        }
      }
      if (await dictionary.nameEntry(PdfName.subtype) == PdfName.widget &&
          widgetPages.containsKey(dictionary)) {
        widgets.add(dictionary);
        accounted.add(dictionary);
      }
      final hasAnyWidgets =
          await dictionary.nameEntry(PdfName.subtype) == PdfName.widget ||
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
  final PdfDictionary source;
  final List<_FieldNode> children;
  final List<PdfDictionary> widgets;
  final bool signed;
  final bool retained;
  _FieldNode(
      this.source, this.children, this.widgets, this.signed, this.retained);
}

class PdfFormMergePlan {
  final PdfDictionary? _form;
  final List<_FieldNode> _roots;
  final Map<PdfDictionary, PdfDictionary> _widgetPages;
  final PdfMergeSignaturePolicy _policy;
  PdfFormMergePlan._(this._form, this._roots, this._widgetPages, this._policy);

  /// Tests whether a selected widget belongs to a populated signature field.
  bool isSignedWidget(PdfDictionary widget) {
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
      PdfDocument output,
      Map<PdfDictionary, PdfDictionary> targets,
      Future<PdfObject> Function(PdfObject) copy,
      {Map<PdfDictionary, List<PdfDictionary>>? repeatedTargets}) async {
    if (_form == null) return;
    final catalog = output.rootCatalog().pdfRepresentation();
    var destination = await catalog.dictionaryEntry(PdfName.acroForm);
    if (destination == null) {
      destination = PdfDictionary()..attachToDocument(output);
      catalog.put(PdfName.acroForm, destination);
    }
    var fields = await destination.arrayEntry(PdfName.fields);
    if (fields == null) {
      fields = PdfArray();
      destination.put(PdfName.fields, fields);
    }
    final usedNames = <String>{};
    Future<void> collectNames(
        PdfDictionary node, String prefix, Set<PdfDictionary> seen) async {
      if (!seen.add(node)) {
        throw FormatException('Output form hierarchy contains a cycle');
      }
      final partial = (await node.stringEntry(PdfName.t))?.decodeMappingText();
      final full = partial == null
          ? prefix
          : prefix.isEmpty
              ? partial
              : '$prefix.$partial';
      if (partial != null) usedNames.add(full);
      final kids = await node.arrayEntry(PdfName.kids);
      if (kids != null) {
        for (var i = 0; i < kids.size(); i++) {
          final child = await kids.dictionaryEntry(i);
          if (child != null && child.containsKey(PdfName.t)) {
            await collectNames(child, full, seen);
          }
        }
      }
    }

    for (var i = 0; i < fields.size(); i++) {
      final field = await fields.dictionaryEntry(i);
      if (field != null) {
        await collectNames(field, '', HashSet<PdfDictionary>.identity());
      }
    }
    Future<Set<String>> incomingNames(_FieldNode node, String name) async {
      final result = <String>{name};
      for (final child in node.children) {
        if (!child.retained) continue;
        final partial =
            (await child.source.stringEntry(PdfName.t))?.decodeMappingText();
        result.addAll(await incomingNames(
            child, partial == null ? name : '$name.$partial'));
      }
      return result;
    }

    final resourceNames = <String, String>{};
    final resources = await _form.dictionaryEntry(PdfName.dr);
    if (resources != null) {
      var destResources = await destination.dictionaryEntry(PdfName.dr);
      if (destResources == null) {
        destResources = PdfDictionary();
        destination.put(PdfName.dr, destResources);
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
              combined = PdfArray();
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
          group = PdfDictionary();
          destResources.put(category.key, group);
        }
        for (final entry in await sourceGroup.entrySet()) {
          final original = entry.key.getValue();
          var name = original;
          var suffix = 2;
          while (group.containsKey(PdfName(name))) {
            name = '${original}_${suffix++}';
          }
          group.put(PdfName(name), await copy(entry.value));
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
          final encoded = PdfName(replacement).toString();
          return encoded.startsWith('/') ? encoded : '/$encoded';
        });
    Future<void> copyEntries(
        PdfDictionary from, PdfDictionary to, Set<String> excluded) async {
      for (final entry in await from.entrySet()) {
        if (excluded.contains(entry.key.getValue())) continue;
        if (entry.key == PdfName.da) {
          final text = await from.stringEntry(entry.key);
          if (text != null) {
            to.put(entry.key,
                PdfString(rewriteAppearance(text.decodeMappingText())));
            continue;
          }
        }
        to.put(entry.key, await copy(entry.value));
      }
    }

    Future<List<PdfDictionary>> attachWidget(
        PdfDictionary source, PdfDictionary target) async {
      final sourcePage = _widgetPages[source];
      final first = targets[sourcePage];
      final pages = repeatedTargets?[sourcePage] ??
          (first == null ? <PdfDictionary>[] : [first]);
      if (pages.isEmpty) throw StateError('Merged widget has no target page');
      final instances = <PdfDictionary>[];
      for (final page in pages) {
        PdfDictionary instance;
        if (instances.isEmpty) {
          instance = target;
        } else {
          instance = PdfDictionary()..attachToDocument(output);
          for (final entry in await target.entrySet()) {
            if (entry.key != PdfName.p) {
              instance.put(entry.key, entry.value);
            }
          }
        }
        instance.put(PdfName.p, page);
        var annotations = await page.arrayEntry(PdfName.annots);
        if (annotations == null) {
          annotations = PdfArray();
          page.put(PdfName.annots, annotations);
        }
        annotations.add(instance);
        instances.add(instance);
      }
      return instances;
    }

    Future<void> preserveStamp(PdfDictionary widget) async {
      final appearance = await widget.dictionaryEntry(PdfName.ap);
      var normal = await appearance?.get(PdfName.n, true);
      if (normal is PdfDictionary && normal is! PdfStream) {
        final state = await widget.nameEntry(PdfName.as);
        normal = state == null ? null : await normal.get(state, true);
      }
      if (normal is! PdfStream) {
        throw UnsupportedError(
            'Signature appearance cannot be preserved without a normal appearance stream');
      }
      final stamp = PdfDictionary()..attachToDocument(output);
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
      stamp.put(PdfName.subtype, PdfName('Stamp'));
      stamp.put(
          PdfName.ap, PdfDictionary()..put(PdfName.n, await copy(normal)));
      await attachWidget(widget, stamp);
    }

    Future<PdfDictionary?> clone(_FieldNode node, PdfDictionary? parent) async {
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
      final field = PdfDictionary()..attachToDocument(output);
      await copyEntries(node.source, field,
          {'Parent', 'Kids', 'P', 'Subtype', 'Rect', 'AP', 'AS', 'V'});
      // Value cloning is deliberately deferred until after signature policy filtering.
      final value = await node.source.get(PdfName.v, true);
      if (value != null) field.put(PdfName.v, await copy(value));
      if (parent != null) field.put(PdfName.parent, parent);
      if (parent == null) {
        final original =
            (await node.source.stringEntry(PdfName.t))?.decodeMappingText();
        if (original != null) {
          var name = original;
          var suffix = 2;
          var names = await incomingNames(node, name);
          while (names.any(usedNames.contains)) {
            name = '${original}_${suffix++}';
            names = await incomingNames(node, name);
          }
          usedNames.addAll(names);
          field.put(PdfName.t, PdfString(name));
        }
        if (!field.containsKey(PdfName.da)) {
          final da = await _form.stringEntry(PdfName.da);
          if (da != null) {
            field.put(PdfName.da,
                PdfString(rewriteAppearance(da.decodeMappingText())));
          }
        }
      }
      final kids = PdfArray();
      for (final child in node.children) {
        final copied = await clone(child, field);
        if (copied != null) kids.add(copied);
      }
      for (final widget in node.widgets) {
        final target = PdfDictionary()..attachToDocument(output);
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
        target.put(PdfName.parent, field);
        for (final instance in await attachWidget(widget, target)) {
          kids.add(instance);
        }
      }
      if (kids.size() > 0) field.put(PdfName.kids, kids);
      return field;
    }

    for (final root in _roots) {
      final cloned = await clone(root, null);
      if (cloned != null) fields.add(cloned);
    }
  }
}
