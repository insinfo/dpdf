import 'dart:typed_data';

import '../pdf_array.dart';
import '../pdf_catalog.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_name_tree.dart';
import '../pdf_object.dart';
import '../pdf_string.dart';
import 'pdf_web_capture_content_set.dart';
import 'web_capture_names.dart';

/// The Web Capture content database of a document.
///
/// ISO 32000-1:2008, 14.10.3: "The mapping may be an association from the
/// resource's URL to the content set, stored in the PDF document's URLS name
/// tree. The mapping may also be an association from a digital identifier...
/// to the content set, stored in the PDF document's IDS name tree. Both
/// associations may be present in the PDF file."
///
/// Entries in either tree "may refer to an array of content sets or a single
/// content set. If the entry is an array, the content sets need not have the
/// same subtype."
class PdfWebCaptureDatabase {
  /// `/IDS`, the name tree keyed by digital identifier.
  static final PdfName idsTree = PdfName.intern('IDS');

  /// `/URLS`, the name tree keyed by canonical URL.
  static final PdfName urlsTree = PdfName.intern('URLS');

  final PdfCatalog _catalog;

  /// Wraps the name dictionary of [catalog].
  PdfWebCaptureDatabase(this._catalog);

  /// The catalogue this database belongs to.
  PdfCatalog catalog() => _catalog;

  /// Registers [contentSet] under its digital identifier in `/IDS`.
  ///
  /// The identifier is taken from the content set's own `/ID`, which is the
  /// value a page or image XObject carries so that its parent content set can
  /// be found (14.10.6).
  Future<void> registerByIdentifier(PdfWebCaptureContentSet contentSet) async {
    final digest = await contentSet.getIdentifier();
    if (digest == null) {
      throw ArgumentError.value(
          contentSet,
          'contentSet',
          'A content set shall carry an /ID before it is registered '
              '(Table 352)');
    }
    await _add(idsTree, PdfString.fromBytes(digest, true), contentSet);
  }

  /// Registers [contentSet] under [url] in `/URLS`.
  ///
  /// The URL is reduced to the canonical form of 14.10.3.2 before it is used
  /// as a key.
  Future<void> registerByUrl(
      String url, PdfWebCaptureContentSet contentSet) async {
    final key = WebCaptureNames.canonicalUrl(url);
    await _add(urlsTree, PdfString(key), contentSet);
  }

  /// The content sets recorded for the digital identifier [digest].
  Future<List<PdfWebCaptureContentSet>> contentSetsForIdentifier(
          Uint8List digest) async =>
      await _lookup(idsTree, PdfString.fromBytes(digest, true));

  /// The content sets recorded for [url], which is canonicalised first.
  Future<List<PdfWebCaptureContentSet>> contentSetsForUrl(String url) async =>
      await _lookup(urlsTree, PdfString(WebCaptureNames.canonicalUrl(url)));

  /// The parent content set of [object], found the way 14.10.6 prescribes.
  ///
  /// "The object's ID entry contains the digital identifier of the parent
  /// content set, which shall be used to locate the parent content set via the
  /// IDS name tree... If the IDS entry for the identifier contains an array of
  /// content sets, the parent may be found by searching the array for the
  /// content set whose O entry includes the child object."
  Future<PdfWebCaptureContentSet?> parentContentSet(
      PdfDictionary object) async {
    final digest =
        (await object.stringEntry(PdfWebCaptureContentSet.identifier))
            ?.getValueBytes();
    if (digest == null) return null;
    final candidates = await contentSetsForIdentifier(digest);
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.single;
    for (final candidate in candidates) {
      for (final member in await candidate.getObjects()) {
        if (identical(member, object)) return candidate;
      }
    }
    return null;
  }

  /// Writes the digital identifier of [contentSet] into the `/ID` entry of
  /// [object], the link 14.10.6 describes between a page or image XObject and
  /// its parent content set.
  static Future<void> markAsMember(
      PdfDictionary object, PdfWebCaptureContentSet contentSet) async {
    final digest = await contentSet.getIdentifier();
    if (digest == null) {
      throw ArgumentError.value(contentSet, 'contentSet',
          'A content set shall carry an /ID (Table 352)');
    }
    object.put(
        PdfWebCaptureContentSet.identifier, PdfString.fromBytes(digest, true));
    object.markChanged();
  }

  /// The keys currently present in [tree], which is [idsTree] or [urlsTree].
  Future<List<PdfString>> keysOf(PdfName tree) async =>
      await (await PdfNameTree.create(_catalog, tree)).getKeys();

  Future<void> _add(
      PdfName tree, PdfString key, PdfWebCaptureContentSet contentSet) async {
    final reference = contentSet.pdfRepresentation().indirectHandle();
    if (reference == null) {
      throw ArgumentError.value(contentSet, 'contentSet',
          'A content set shall be an indirect object before it is registered');
    }
    final existing =
        await (await PdfNameTree.create(_catalog, tree)).getEntry(key);
    PdfObject value;
    if (existing == null) {
      value = reference;
    } else if (existing is PdfArray) {
      final merged = PdfArray.fromArray(existing);
      if (!_holdsReference(merged, reference)) merged.add(reference);
      value = merged;
    } else {
      final merged = PdfArray();
      merged.add(existing);
      if (!_holdsReference(merged, reference)) merged.add(reference);
      value = merged;
    }
    await _catalog.addNameToNameTree(key, value, tree);
  }

  Future<List<PdfWebCaptureContentSet>> _lookup(
      PdfName tree, PdfString key) async {
    final entry =
        await (await PdfNameTree.create(_catalog, tree)).getEntry(key);
    final resolved = await _resolve(entry);
    if (resolved == null) return const [];
    final result = <PdfWebCaptureContentSet>[];
    if (resolved is PdfArray) {
      for (var i = 0; i < resolved.size(); i++) {
        final member = await _resolve(await resolved.get(i, false));
        if (member is PdfDictionary) {
          final wrapped = await PdfWebCaptureContentSet.wrap(member);
          if (wrapped != null) result.add(wrapped);
        }
      }
      return result;
    }
    if (resolved is PdfDictionary) {
      final wrapped = await PdfWebCaptureContentSet.wrap(resolved);
      if (wrapped != null) result.add(wrapped);
    }
    return result;
  }

  static Future<PdfObject?> _resolve(PdfObject? object) async {
    if (object is PdfIndirectReference) {
      return await object.targetObject(true) ?? object;
    }
    return object;
  }

  static bool _holdsReference(PdfArray array, PdfIndirectReference reference) {
    for (final entry in array.toList()) {
      if (entry is PdfIndirectReference &&
          entry.objectNumber() == reference.objectNumber() &&
          entry.generationNumber() == reference.generationNumber()) {
        return true;
      }
    }
    return false;
  }
}
