import 'dart:collection';
import 'dart:typed_data';

import 'pdf_array.dart';
import 'pdf_dictionary.dart';
import 'pdf_document.dart';
import 'pdf_name.dart';
import 'pdf_object.dart';
import 'pdf_stream.dart';

/// Copies a graph of PDF objects into one destination document.
/// Reuse a copier when multiple roots must retain shared object identity.
class PdfObjectCopier {
  final PdfDocument destination;
  final Set<String> forbiddenUnmappedTypes;
  final bool deferIndirectRegistration;
  final _copies = HashMap<PdfObject, PdfObject>.identity();
  final _pending = HashSet<PdfObject>.identity();
  PdfObjectCopier(this.destination,
      {this.forbiddenUnmappedTypes = const {},
      this.deferIndirectRegistration = false}) {
    if (destination.lifecycleClosed() || destination.outputWriter() == null) {
      throw StateError('The destination must be an open writable document.');
    }
  }

  /// Registers roots before copying their children, allowing forward links.
  void register(PdfObject source, PdfObject target) {
    if (_copies.containsKey(source)) {
      throw StateError('The source object already has a destination.');
    }
    _copies[source] = target;
    _attach(target);
  }

  /// Publishes staged objects after a whole batch has passed validation.
  void commit() {
    for (final object in _pending) {
      object.attachToDocument(destination);
    }
    _pending.clear();
  }

  void _attach(PdfObject object) {
    if (deferIndirectRegistration) {
      _pending.add(object);
    } else {
      object.attachToDocument(destination);
    }
  }

  Future<void> copyDictionaryEntries(PdfDictionary source, PdfDictionary target,
      {Set<PdfName> excludedKeys = const {}}) async {
    for (final entry in await source.entrySet()) {
      if (excludedKeys.contains(entry.key)) continue;
      if (source is PdfStream && entry.key == PdfName.length) {
        continue;
      }
      target.put(entry.key, await copy(entry.value));
    }
  }

  Future<PdfObject> copy(PdfObject source) async {
    final references = HashSet<PdfIndirectReference>.identity();
    while (source is PdfIndirectReference) {
      if (!references.add(source)) {
        throw FormatException('Cyclic indirect reference chain.');
      }
      final target = await source.targetObject(true);
      if (target == null) throw FormatException('Unresolved object reference.');
      source = target;
    }
    final prior = _copies[source];
    if (prior != null) return prior;
    if (source is PdfDictionary) {
      final type = (await source.nameEntry(PdfName.type))?.getValue();
      if (forbiddenUnmappedTypes.contains(type)) {
        throw UnsupportedError(
            'The copied graph references an unselected /$type object.');
      }
      final PdfDictionary target;
      if (source is PdfStream) {
        final bytes = await source.getBytes(false);
        target = PdfStream.withBytes(bytes ?? Uint8List(0), 0);
      } else {
        target = PdfDictionary();
      }
      _copies[source] = target;
      _attach(target);
      await copyDictionaryEntries(source, target);
      return target;
    }
    if (source is PdfArray) {
      final target = PdfArray();
      _copies[source] = target;
      _attach(target);
      for (var i = 0; i < source.size(); i++) {
        final item = await source.get(i, false);
        if (item == null) throw FormatException('Missing array item.');
        target.add(await copy(item));
      }
      return target;
    }
    final target = source.clone();
    _copies[source] = target;
    if (source.indirectHandle() != null) _attach(target);
    return target;
  }
}
